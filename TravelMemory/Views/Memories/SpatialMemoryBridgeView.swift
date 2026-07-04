//
//  SpatialMemoryBridgeView.swift
//  TravelMemory
//
//  Explore tab — real MapKit map with trip destination pins
//  and a draggable destination list overlay.
//

import SwiftUI
import SwiftData
import MapKit

// MARK: - Geocoding Cache

@MainActor
class TripGeocodingService: ObservableObject {
    @Published var coordinates: [UUID: CLLocationCoordinate2D] = [:]
    private var geocoder = CLGeocoder()
    private var pending = Set<UUID>()
    
    func geocode(trips: [Trip]) {
        for trip in trips where !trip.destination.isEmpty {
            guard coordinates[trip.id] == nil, !pending.contains(trip.id) else { continue }
            pending.insert(trip.id)
            
            let tripId = trip.id
            let dest = trip.destination
            
            CLGeocoder().geocodeAddressString(dest) { [weak self] placemarks, _ in
                Task { @MainActor in
                    if let coord = placemarks?.first?.location?.coordinate {
                        self?.coordinates[tripId] = coord
                    }
                    self?.pending.remove(tripId)
                }
            }
        }
    }
}

// MARK: - Map Pin Model

struct TripMapPin: Identifiable {
    let id: UUID
    let name: String
    let dateRange: String
    let status: TripStatus
    let coordinate: CLLocationCoordinate2D
    let trip: Trip
}

struct NearbyPlace: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let category: String
}

// MARK: - Explore View

struct SpatialMemoryBridgeView: View {
    @Query(sort: \Trip.startDate, order: .forward) private var trips: [Trip]
    @StateObject private var geoService = TripGeocodingService()
    @State private var selectedPin: TripMapPin?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var appeared = false
    @State private var nearbyResults: [NearbyPlace] = []
    @State private var searchCategory = ""
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var hasSetInitialPosition = false
    @FocusState private var searchFocused: Bool
    
    private var mapPins: [TripMapPin] {
        trips.compactMap { trip in
            guard let coord = geoService.coordinates[trip.id] else { return nil }
            return TripMapPin(
                id: trip.id,
                name: trip.destination.isEmpty ? trip.name : trip.destination,
                dateRange: trip.dateRangeText,
                status: trip.status,
                coordinate: coord,
                trip: trip
            )
        }
    }
    
    /// Find the best starting trip (next upcoming, or most recent)
    private var primaryTrip: Trip? {
        let now = Date()
        let upcoming = trips.filter { $0.startDate >= now }.sorted { $0.startDate < $1.startDate }
        if let next = upcoming.first { return next }
        return trips.sorted { $0.startDate > $1.startDate }.first
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            mapLayer
            overlayLayer
        }
        .navigationBarHidden(true)
        .onChange(of: trips) { _, newTrips in
            geoService.geocode(trips: newTrips)
        }
        .onAppear {
            geoService.geocode(trips: trips)
            withAnimation { appeared = true }
            setInitialPosition()
        }
        .animation(.easeOut(duration: 0.3), value: selectedPin?.id)
    }
    
    // MARK: - Map Layer
    
    @ViewBuilder
    private var mapLayer: some View {
        if trips.isEmpty {
            darkMapFallback
        } else {
            Map(position: $cameraPosition) {
                ForEach(mapPins) { pin in
                    Annotation(pin.name, coordinate: pin.coordinate) {
                        mapPinView(pin)
                    }
                }
                // Nearby search results
                ForEach(nearbyResults) { place in
                    Annotation(place.name, coordinate: place.coordinate) {
                        nearbyPinView(place)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .including([.restaurant, .hotel, .beach, .marina, .museum, .nationalPark, .park])))
            .ignoresSafeArea(edges: .top)
        }
    }
    
    // MARK: - Set Initial Position
    
    private func setInitialPosition() {
        guard !hasSetInitialPosition else { return }
        hasSetInitialPosition = true
        
        guard let trip = primaryTrip else { return }
        
        // Priority: 1) Hotel address  2) Airport  3) Trip destination
        let hotelAddress = trip.hotels.first?.address ?? ""
        let departureAirport = trip.flights.first?.departureCity ?? ""
        let destination = trip.destination
        
        let locationToGeocode: String
        if !hotelAddress.isEmpty {
            locationToGeocode = hotelAddress
        } else if !departureAirport.isEmpty {
            locationToGeocode = departureAirport + " airport"
        } else if !destination.isEmpty {
            locationToGeocode = destination
        } else {
            return
        }
        
        CLGeocoder().geocodeAddressString(locationToGeocode) { placemarks, _ in
            if let coord = placemarks?.first?.location?.coordinate {
                withAnimation {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: coord,
                        latitudinalMeters: 5000,
                        longitudinalMeters: 5000
                    ))
                }
            }
        }
    }
    
    // MARK: - Overlay Layer
    
    @ViewBuilder
    private var overlayLayer: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                VoyagerTopBar()
                
                // Search bar
                if !trips.isEmpty {
                    searchBar
                }
            }
            .background(
                LinearGradient(
                    colors: [Color.voyagerBackground.opacity(0.95), Color.voyagerBackground.opacity(0.7), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            
            Spacer()
            
            bottomPanel
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            
            TextField("Search restaurants, activities...", text: $searchText)
                .font(VoyagerFont.bodySmall)
                .foregroundStyle(Color.voyagerOnSurface)
                .focused($searchFocused)
                .onSubmit {
                    searchOnMap()
                }
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    withAnimation {
                        nearbyResults = []
                        searchCategory = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
            
            if isSearching {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Button {
                    searchOnMap()
                } label: {
                    Text("Search")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.voyagerPrimary)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(10)
        .background(Color.voyagerSurfaceContainerLow.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.voyagerOutlineVariant.opacity(0.3), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - Search on Map
    
    private func searchOnMap() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        searchFocused = false
        
        // Find the best location to search near
        guard let trip = primaryTrip else { return }
        let hotelAddress = trip.hotels.first?.address ?? ""
        let dest = trip.destination
        let searchNear = hotelAddress.isEmpty ? dest : hotelAddress
        
        guard !searchNear.isEmpty else { return }
        
        searchCategory = query.capitalized
        isSearching = true
        
        CLGeocoder().geocodeAddressString(searchNear) { placemarks, _ in
            guard let location = placemarks?.first?.location else {
                DispatchQueue.main.async { isSearching = false }
                return
            }
            
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 8000,
                longitudinalMeters: 8000
            )
            
            MKLocalSearch(request: request).start { response, _ in
                DispatchQueue.main.async {
                    isSearching = false
                    guard let items = response?.mapItems else { return }
                    
                    withAnimation {
                        nearbyResults = items.prefix(15).map { item in
                            NearbyPlace(
                                name: item.name ?? "Unknown",
                                address: item.placemark.formattedAddress ?? item.placemark.title ?? "",
                                coordinate: item.placemark.coordinate,
                                category: query
                            )
                        }
                        selectedPin = nil
                        
                        cameraPosition = .region(MKCoordinateRegion(
                            center: location.coordinate,
                            latitudinalMeters: 6000,
                            longitudinalMeters: 6000
                        ))
                    }
                }
            }
        }
    }
    
    // MARK: - Bottom Panel
    
    @ViewBuilder
    private var bottomPanel: some View {
        if trips.isEmpty {
            emptyState
                .padding(.bottom, 120)
        } else if !nearbyResults.isEmpty {
            nearbyResultsList
                .padding(.horizontal, VoyagerSpacing.marginMain)
                .padding(.bottom, 90)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let pin = selectedPin {
            selectedPinCard(pin)
                .padding(.horizontal, VoyagerSpacing.marginMain)
                .padding(.bottom, 110)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            destinationsPanel
                .padding(.bottom, 90)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    // MARK: - Map Pin View
    
    private func mapPinView(_ pin: TripMapPin) -> some View {
        let color: Color = {
            switch pin.status {
            case .planning: return .voyagerPrimary
            case .live: return .voyagerPrimaryAccent
            case .completed: return .voyagerTertiary
            }
        }()
        
        return VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 32, height: 32)
                    .shadow(color: color.opacity(0.5), radius: 8)
                
                Image(systemName: "airplane")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            
            // Pin tail
            Triangle()
                .fill(color)
                .frame(width: 12, height: 8)
                .offset(y: -2)
        }
        .onTapGesture {
            withAnimation { selectedPin = pin }
        }
    }
    
    // MARK: - Selected Pin Card
    
    private func selectedPinCard(_ pin: TripMapPin) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Circle()
                    .fill(Color.voyagerPrimary.opacity(0.12))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.voyagerPrimary)
                    )
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(pin.name)
                        .font(VoyagerFont.bodyLarge)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.voyagerOnSurface)
                    Text(pin.dateRange)
                        .font(VoyagerFont.bodySmall)
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
                
                Spacer()
                
                Button {
                    withAnimation { selectedPin = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
            
            // Quick-action map links
            HStack(spacing: 8) {
                mapSearchButton(icon: "fork.knife", label: "Restaurants", query: "restaurants", destination: pin.name)
                mapSearchButton(icon: "bed.double", label: "Hotels", query: "hotels", destination: pin.name)
                mapSearchButton(icon: "star", label: "Attractions", query: "attractions", destination: pin.name)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: VoyagerRadius.large)
                .fill(Color.voyagerCard.opacity(0.95))
                .background(
                    RoundedRectangle(cornerRadius: VoyagerRadius.large)
                        .fill(.ultraThinMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerRadius.large)
                .stroke(Color.voyagerOutlineVariant.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
    
    // MARK: - Destinations Panel
    
    private var destinationsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Drag handle
            Capsule()
                .fill(Color.voyagerOutlineVariant.opacity(0.4))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            
            Text("YOUR DESTINATIONS")
                .font(VoyagerFont.labelCaps)
                .tracking(1.2)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                .padding(.horizontal, 4)
            
            ForEach(Array(trips.filter { !$0.destination.isEmpty }.enumerated()), id: \.element.id) { idx, trip in
                HStack(spacing: 14) {
                    Circle()
                        .fill(Color.voyagerPrimary.opacity(0.12))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.voyagerPrimary)
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trip.destination)
                            .font(VoyagerFont.bodyLarge)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.voyagerOnSurface)
                        Text(trip.dateRangeText)
                            .font(VoyagerFont.bodySmall)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                    
                    Spacer()
                    
                    Button {
                        openInMaps(destination: trip.destination)
                    } label: {
                        Image(systemName: "map")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.voyagerPrimary)
                            .padding(6)
                            .background(Color.voyagerPrimary.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                .staggeredAppear(index: idx, appeared: appeared)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(
            RoundedRectangle(cornerRadius: VoyagerRadius.large)
                .fill(Color.voyagerCard.opacity(0.9))
                .background(
                    RoundedRectangle(cornerRadius: VoyagerRadius.large)
                        .fill(.ultraThinMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerRadius.large)
                .stroke(Color.voyagerOutlineVariant.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 16, y: -4)
        .padding(.horizontal, VoyagerSpacing.marginMain)
    }
    
    // MARK: - Nearby Pin View
    
    private func nearbyPinView(_ place: NearbyPlace) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.voyagerTertiary)
                    .frame(width: 26, height: 26)
                    .shadow(color: Color.voyagerTertiary.opacity(0.5), radius: 6)
                Image(systemName: categoryIcon(searchCategory))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            Triangle()
                .fill(Color.voyagerTertiary)
                .frame(width: 10, height: 6)
                .offset(y: -2)
        }
    }
    
    // MARK: - Nearby Results List
    
    private var nearbyResultsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: categoryIcon(searchCategory))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.voyagerTertiary)
                Text("\(searchCategory.uppercased()) NEARBY")
                    .font(VoyagerFont.labelCaps)
                    .tracking(1.0)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                
                Spacer()
                
                Button {
                    withAnimation {
                        nearbyResults = []
                        searchCategory = ""
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("CLEAR")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.voyagerSurfaceContainerHigh)
                    .clipShape(Capsule())
                }
            }
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(nearbyResults.prefix(8)) { place in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color.voyagerTertiary.opacity(0.12))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Image(systemName: categoryIcon(searchCategory))
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.voyagerTertiary)
                                )
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(place.name)
                                    .font(VoyagerFont.bodySmall)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.voyagerOnSurface)
                                    .lineLimit(1)
                                if !place.address.isEmpty {
                                    Text(place.address)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                                        .lineLimit(1)
                                }
                            }
                            
                            Spacer()
                            
                            Button {
                                openInAppleMaps(place: place)
                            } label: {
                                Image(systemName: "map")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.voyagerPrimary)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: VoyagerRadius.large)
                .fill(Color.voyagerCard.opacity(0.95))
                .background(
                    RoundedRectangle(cornerRadius: VoyagerRadius.large)
                        .fill(.ultraThinMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerRadius.large)
                .stroke(Color.voyagerOutlineVariant.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
    
    // MARK: - Map Search Helpers
    
    private func mapSearchButton(icon: String, label: String, query: String, destination: String) -> some View {
        Button {
            searchNearby(query: query, destination: destination)
        } label: {
            HStack(spacing: 5) {
                if isSearching && searchCategory == label {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(Color.voyagerPrimary)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color.voyagerPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.voyagerPrimary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.voyagerPrimary.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func searchNearby(query: String, destination: String) {
        searchCategory = query.capitalized
        isSearching = true
        
        // First geocode the destination, then search nearby
        CLGeocoder().geocodeAddressString(destination) { placemarks, _ in
            guard let location = placemarks?.first?.location else {
                DispatchQueue.main.async { isSearching = false }
                return
            }
            
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 5000,
                longitudinalMeters: 5000
            )
            
            MKLocalSearch(request: request).start { response, _ in
                DispatchQueue.main.async {
                    isSearching = false
                    guard let items = response?.mapItems else { return }
                    
                    withAnimation {
                        nearbyResults = items.prefix(10).map { item in
                            NearbyPlace(
                                name: item.name ?? "Unknown",
                                address: item.placemark.title ?? "",
                                coordinate: item.placemark.coordinate,
                                category: query
                            )
                        }
                        selectedPin = nil
                        
                        // Zoom to show results
                        cameraPosition = .region(MKCoordinateRegion(
                            center: location.coordinate,
                            latitudinalMeters: 6000,
                            longitudinalMeters: 6000
                        ))
                    }
                }
            }
        }
    }
    
    private func openInAppleMaps(place: NearbyPlace) {
        let lat = place.coordinate.latitude
        let lng = place.coordinate.longitude
        let query = place.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "maps://?q=\(query)&ll=\(lat),\(lng)&z=17") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openInMaps(destination: String) {
        let query = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "maps://?q=\(query)") {
            UIApplication.shared.open(url)
        }
    }
    
    private func categoryIcon(_ category: String) -> String {
        switch category.lowercased() {
        case "restaurants": return "fork.knife"
        case "hotels": return "bed.double"
        case "attractions": return "star"
        default: return "mappin"
        }
    }
    
    // MARK: - Dark Map Fallback
    
    private var darkMapFallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#0D1117"), Color(hex: "#161B22"), Color(hex: "#0D1117")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Subtle decorative grid
            GeometryReader { geo in
                ForEach(0..<8, id: \.self) { i in
                    Rectangle()
                        .fill(Color.voyagerSurfaceContainerHigh.opacity(0.08))
                        .frame(width: 1, height: geo.size.height)
                        .offset(x: CGFloat(i) * 55 - 200)
                        .rotationEffect(.degrees(Double(i % 2 == 0 ? 15 : -10)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.voyagerPrimary.opacity(0.06))
                    .frame(width: 120, height: 120)
                Image(systemName: "map")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(Color.voyagerPrimary.opacity(0.6))
                    .symbolEffect(.pulse, options: .repeating)
            }
            
            VStack(spacing: 8) {
                Text("No Destinations Yet")
                    .font(VoyagerFont.headlineMedium)
                    .foregroundStyle(Color.voyagerOnSurface)
                Text("Your trip destinations will appear\non the map as you add them")
                    .font(VoyagerFont.bodySmall)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
    }
}

// MARK: - Triangle Shape (for map pin tail)

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
