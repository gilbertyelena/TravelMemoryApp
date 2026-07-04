//
//  EditDiningView.swift
//  TravelMemory
//
//  Edit a restaurant reservation with name search, map browse,
//  address, time, and party size.
//

import SwiftUI
import SwiftData
import MapKit

// MKMapItem Identifiable conformance for Map annotations
extension MKMapItem: @retroactive Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

// MARK: - Restaurant Search Manager

@MainActor
class RestaurantSearchManager: ObservableObject {
    @Published var results: [MKMapItem] = []
    @Published var isSearching = false
    
    private var searchTask: Task<Void, Never>?
    var searchRegion: MKCoordinateRegion?
    
    func search(query: String) {
        searchTask?.cancel()
        
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            
            // Search with the exact name (don't append "restaurant" — it confuses pasted names)
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed
            request.resultTypes = .pointOfInterest
            if let region = searchRegion {
                request.region = region
            }
            
            let search = MKLocalSearch(request: request)
            do {
                let response = try await search.start()
                if !Task.isCancelled {
                    // Filter results to only those within ~50km of search region center
                    let filtered: [MKMapItem]
                    if let region = searchRegion {
                        let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
                        filtered = response.mapItems.filter { item in
                            let itemLoc = CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
                            return center.distance(from: itemLoc) < 50_000 // 50km
                        }
                    } else {
                        filtered = Array(response.mapItems)
                    }
                    self.results = Array(filtered.prefix(6))
                }
            } catch {
                if !Task.isCancelled {
                    self.results = []
                }
            }
            self.isSearching = false
        }
    }
    
    func searchArea(region: MKCoordinateRegion) {
        searchTask?.cancel()
        isSearching = true
        
        searchTask = Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "restaurant"
            request.resultTypes = .pointOfInterest
            request.region = region
            
            let search = MKLocalSearch(request: request)
            do {
                let response = try await search.start()
                if !Task.isCancelled {
                    self.results = response.mapItems
                }
            } catch {
                if !Task.isCancelled {
                    self.results = []
                }
            }
            self.isSearching = false
        }
    }
    
    func clear() {
        searchTask?.cancel()
        results = []
    }
}

// MARK: - Edit Dining View

struct EditDiningView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var reservation: DiningReservation
    
    @State private var restaurantName = ""
    @State private var address = ""
    @State private var reservationTime = Date()
    @State private var partySize = 2
    @State private var confirmationCode = ""
    @State private var notes = ""
    @State private var showDeleteConfirm = false
    @State private var showMapBrowser = false
    
    @StateObject private var searchManager = RestaurantSearchManager()
    @State private var isNameFieldFocused = false
    @FocusState private var nameFieldFocus: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.voyagerBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: VoyagerSpacing.stackLarge) {
                        // Restaurant name with search
                        restaurantNameSection
                        
                        formField(title: "ADDRESS", placeholder: "Full address", text: $address)
                        
                        dateField(title: "RESERVATION TIME", date: $reservationTime)
                        
                        // Party size stepper
                        partySizeSection
                        
                        formField(title: "CONFIRMATION CODE", placeholder: "Optional", text: $confirmationCode)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOTES")
                                .font(VoyagerFont.labelCapsFallback)
                                .tracking(1.0)
                                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                            TextField("Dietary requirements, special requests...", text: $notes, axis: .vertical)
                                .font(VoyagerFont.bodyLargeFallback)
                                .foregroundStyle(Color.voyagerOnSurface)
                                .lineLimit(2...4)
                                .padding(12)
                                .background(Color.voyagerInputBackground)
                                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                                .overlay(
                                    RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                                        .stroke(Color.voyagerInputBorder, lineWidth: 1)
                                )
                        }
                        
                        Button { save() } label: { Text("SAVE") }
                            .buttonStyle(VoyagerPrimaryButtonStyle())
                            .padding(.top, 8)
                        
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Text("DELETE RESERVATION")
                                .font(VoyagerFont.labelCapsFallback)
                                .tracking(0.6)
                                .foregroundStyle(Color.voyagerError)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Edit Reservation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
            .alert("Delete Reservation?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    modelContext.delete(reservation)
                    try? modelContext.save()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showMapBrowser) {
                RestaurantMapBrowser(
                    destination: reservation.trip?.destination ?? "",
                    accommodationName: reservation.trip?.hotels.first?.hotelName ?? "",
                    accommodationAddress: reservation.trip?.hotels.first?.address ?? "",
                    searchManager: searchManager
                ) { mapItem in
                    selectRestaurant(mapItem)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            loadValues()
            geocodeDestination()
        }
    }
    
    // MARK: - Restaurant Name with Search
    
    private var restaurantNameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RESTAURANT")
                    .font(VoyagerFont.labelCapsFallback)
                    .tracking(1.0)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                
                Spacer()
                
                // Map buttons
                HStack(spacing: 6) {
                    // In-app map - tap to select
                    Button {
                        nameFieldFocus = false
                        showMapBrowser = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 11))
                            Text("SELECT ON MAP")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.5)
                        }
                        .foregroundStyle(Color(hex: "#FFB868"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(hex: "#FFB868").opacity(0.1))
                        .clipShape(Capsule())
                    }
                    
                    // Apple Maps - for ratings
                    Button {
                        nameFieldFocus = false
                        openAppleMapsForRestaurants()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "star.circle")
                                .font(.system(size: 11))
                            Text("RATINGS")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.5)
                        }
                        .foregroundStyle(Color.voyagerPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.voyagerPrimary.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
            }
            
            TextField("Search restaurants near your stay...", text: $restaurantName)
                .font(VoyagerFont.bodyLargeFallback)
                .foregroundStyle(Color.voyagerOnSurface)
                .padding(12)
                .background(Color.voyagerInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                        .stroke(nameFieldFocus ? Color.voyagerPrimary.opacity(0.6) : Color.voyagerInputBorder, lineWidth: 1)
                )
                .focused($nameFieldFocus)
                .onChange(of: restaurantName) { _, newValue in
                    if nameFieldFocus {
                        searchManager.search(query: newValue)
                    }
                }
                .onChange(of: nameFieldFocus) { _, focused in
                    isNameFieldFocused = focused
                    if !focused {
                        // Delay clearing to allow tap on result
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if !nameFieldFocus { searchManager.clear() }
                        }
                    }
                }
            
            // Search results dropdown
            if !searchManager.results.isEmpty && isNameFieldFocused {
                VStack(spacing: 0) {
                    ForEach(searchManager.results, id: \.self) { item in
                        Button {
                            selectRestaurant(item)
                            nameFieldFocus = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "fork.knife")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(hex: "#FFB868"))
                                    .frame(width: 22)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name ?? "Restaurant")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Color.voyagerOnSurface)
                                        .lineLimit(1)
                                    
                                    if let address = item.placemark.formattedAddress {
                                        Text(address)
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                                            .lineLimit(1)
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        
                        if item != searchManager.results.last {
                            Divider().opacity(0.2)
                        }
                    }
                }
                .background(Color.voyagerSurfaceContainerHigh)
                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                        .stroke(Color.voyagerOutlineVariant.opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            }
            
            if searchManager.isSearching {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Searching nearby...")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
                .padding(.top, 2)
            }
        }
    }
    
    // MARK: - Party Size
    
    private var partySizeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PARTY SIZE")
                .font(VoyagerFont.labelCapsFallback)
                .tracking(1.0)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            
            HStack(spacing: 16) {
                Button {
                    if partySize > 1 { partySize -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(partySize > 1 ? Color.voyagerPrimary : Color.voyagerSurfaceContainerHighest)
                }
                
                Text("\(partySize)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.voyagerOnSurface)
                    .frame(width: 40)
                
                Button {
                    if partySize < 20 { partySize += 1 }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.voyagerPrimary)
                }
                
                Spacer()
                
                Text(partySize == 1 ? "guest" : "guests")
                    .font(VoyagerFont.bodySmallFallback)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }
            .padding(12)
            .background(Color.voyagerInputBackground)
            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
        }
    }
    
    // MARK: - Data
    
    private func geocodeDestination() {
        // Use hotel address first (most precise), fall back to trip destination
        let hotelAddress = reservation.trip?.hotels.first?.address ?? ""
        let tripDest = reservation.trip?.destination ?? ""
        let locationToGeocode = hotelAddress.isEmpty ? tripDest : hotelAddress
        
        guard !locationToGeocode.isEmpty else { return }
        
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(locationToGeocode) { placemarks, _ in
            if let loc = placemarks?.first?.location {
                self.searchManager.searchRegion = MKCoordinateRegion(
                    center: loc.coordinate,
                    latitudinalMeters: 30_000,
                    longitudinalMeters: 30_000
                )
            } else if !tripDest.isEmpty && !hotelAddress.isEmpty {
                // Hotel geocode failed, try trip destination
                let fallbackGeocoder = CLGeocoder()
                fallbackGeocoder.geocodeAddressString(tripDest) { placemarks, _ in
                    if let loc = placemarks?.first?.location {
                        self.searchManager.searchRegion = MKCoordinateRegion(
                            center: loc.coordinate,
                            latitudinalMeters: 30_000,
                            longitudinalMeters: 30_000
                        )
                    }
                }
            }
        }
    }
    
    private func selectRestaurant(_ item: MKMapItem) {
        restaurantName = item.name ?? ""
        address = item.placemark.formattedAddress ?? ""
        searchManager.clear()
    }
    
    private func loadValues() {
        restaurantName = reservation.restaurantName
        address = reservation.address
        reservationTime = reservation.reservationTime
        partySize = reservation.partySize
        confirmationCode = reservation.confirmationCode
        notes = reservation.notes
    }
    
    private func save() {
        reservation.restaurantName = restaurantName
        reservation.address = address
        reservation.reservationTime = reservationTime
        reservation.partySize = partySize
        reservation.confirmationCode = confirmationCode
        reservation.notes = notes
        try? modelContext.save()
        dismiss()
    }
    
    private func openAppleMapsForRestaurants() {
        // Use accommodation address if available, otherwise trip destination
        let accomAddress = reservation.trip?.hotels.first?.address ?? ""
        let dest = reservation.trip?.destination ?? ""
        let locationQuery = accomAddress.isEmpty ? dest : accomAddress
        
        guard !locationQuery.isEmpty else { return }
        
        // Geocode to get coordinates, then open Apple Maps centered there
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(locationQuery) { placemarks, _ in
            let lat: Double
            let lng: Double
            
            if let loc = placemarks?.first?.location {
                lat = loc.coordinate.latitude
                lng = loc.coordinate.longitude
            } else {
                if let region = searchManager.searchRegion {
                    lat = region.center.latitude
                    lng = region.center.longitude
                } else {
                    return
                }
            }
            
            // Apple Maps URL with restaurant search at hotel coordinates
            let urlString = "maps://?q=restaurants&ll=\(lat),\(lng)&z=16"
            
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
        }
    }
    
    private func formField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(VoyagerFont.labelCapsFallback)
                .tracking(1.0)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            TextField(placeholder, text: text)
                .font(VoyagerFont.bodyLargeFallback)
                .foregroundStyle(Color.voyagerOnSurface)
                .padding(12)
                .background(Color.voyagerInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                        .stroke(Color.voyagerInputBorder, lineWidth: 1)
                )
        }
    }
    
    private func dateField(title: String, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(VoyagerFont.labelCapsFallback)
                .tracking(1.0)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            DatePicker("", selection: date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(Color.voyagerPrimary)
                .padding(10)
                .background(Color.voyagerInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
        }
    }
}

// MARK: - Formatted Address Helper

extension CLPlacemark {
    var formattedAddress: String? {
        var parts: [String] = []
        if let street = thoroughfare {
            if let number = subThoroughfare { parts.append("\(number) \(street)") }
            else { parts.append(street) }
        }
        if let city = locality { parts.append(city) }
        if let country = country { parts.append(country) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

// MARK: - Map Pin Annotation

struct MapPinAnnotation: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let isStay: Bool
    let mapItem: MKMapItem?
}

// MARK: - Restaurant Map Browser

struct RestaurantMapBrowser: View {
    let destination: String
    let accommodationName: String
    let accommodationAddress: String
    @ObservedObject var searchManager: RestaurantSearchManager
    let onSelect: (MKMapItem) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 38.72, longitude: -9.14),
        span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
    )
    @State private var selectedItem: MKMapItem?
    @State private var hasGeocoded = false
    @State private var searchText = ""
    @State private var stayCoordinate: CLLocationCoordinate2D?
    @State private var stayName: String = ""
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(coordinateRegion: $region, annotationItems: allAnnotations) { ann in
                    MapAnnotation(coordinate: ann.coordinate) {
                        if ann.isStay {
                            // Accommodation pin
                            VStack(spacing: 2) {
                                ZStack {
                                    Circle()
                                        .fill(Color.voyagerTertiary)
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "bed.double.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white)
                                }
                                .shadow(color: Color.voyagerTertiary.opacity(0.5), radius: 6, y: 2)
                                
                                Text(ann.name)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.voyagerTertiary.opacity(0.85))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        } else {
                            // Restaurant pin
                            Button {
                                selectedItem = ann.mapItem
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: "fork.knife.circle.fill")
                                        .font(.system(size: 30))
                                        .foregroundStyle(
                                            selectedItem == ann.mapItem ? Color(hex: "#FFB868") : Color.voyagerPrimary
                                        )
                                        .background(Circle().fill(.white).padding(3))
                                    
                                    if selectedItem == ann.mapItem {
                                        Text(ann.name)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.black.opacity(0.75))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                            }
                        }
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                
                // Search bar overlay
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                        TextField("Search restaurants...", text: $searchText)
                            .font(VoyagerFont.bodySmallFallback)
                            .foregroundStyle(Color.voyagerOnSurface)
                            .onSubmit {
                                searchInArea()
                            }
                        
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchManager.searchArea(region: region)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                            }
                        }
                        
                        Button {
                            searchInArea()
                        } label: {
                            Text("Search")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.voyagerPrimary)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    
                    Spacer()
                }
                
                // Selected restaurant card
                if let item = selectedItem {
                    selectedRestaurantCard(item)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Search this area button
                if selectedItem == nil {
                    Button {
                        searchManager.searchArea(region: region)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                            Text("Search this area")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.voyagerPrimary)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Find Restaurant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            geocodeAndSearch()
        }
    }
    
    private func selectedRestaurantCard(_ item: MKMapItem) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name ?? "Restaurant")
                        .font(VoyagerFont.bodyLargeFallback)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.voyagerOnSurface)
                    
                    if let addr = item.placemark.formattedAddress {
                        Text(addr)
                            .font(VoyagerFont.bodySmallFallback)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                            .lineLimit(2)
                    }
                    
                    if let phone = item.phoneNumber {
                        HStack(spacing: 4) {
                            Image(systemName: "phone")
                                .font(.system(size: 11))
                            Text(phone)
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(Color.voyagerPrimary)
                    }
                }
                
                Spacer()
                
                Button {
                    withAnimation { selectedItem = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
            
            HStack(spacing: 10) {
                // Select button
                Button {
                    onSelect(item)
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                        Text("SELECT")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(0.6)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(hex: "#FFB868"))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                // Open in Google Maps
                Button {
                    let coord = item.placemark.coordinate
                    let query = (item.name ?? "restaurant").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(query)&center=\(coord.latitude),\(coord.longitude)") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 14))
                        Text("GOOGLE")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(0.6)
                    }
                    .foregroundStyle(Color.voyagerPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.voyagerPrimary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.voyagerPrimary.opacity(0.3), lineWidth: 1)
                    )
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
    
    // All annotations: stay pin + restaurant pins
    private var allAnnotations: [MapPinAnnotation] {
        var pins: [MapPinAnnotation] = []
        
        // Add accommodation pin
        if let coord = stayCoordinate {
            pins.append(MapPinAnnotation(
                id: "stay",
                name: stayName.isEmpty ? "Your Stay" : stayName,
                coordinate: coord,
                isStay: true,
                mapItem: nil
            ))
        }
        
        // Add restaurant pins
        for item in searchManager.results {
            pins.append(MapPinAnnotation(
                id: "r-\(item.hash)",
                name: item.name ?? "Restaurant",
                coordinate: item.placemark.coordinate,
                isStay: false,
                mapItem: item
            ))
        }
        
        return pins
    }
    
    private func geocodeAndSearch() {
        guard !hasGeocoded else { return }
        hasGeocoded = true
        
        // Geocode accommodation first if available
        let accomAddr = accommodationAddress.isEmpty ? nil : accommodationAddress
        let destAddr = destination.isEmpty ? nil : destination
        let geocoder = CLGeocoder()
        
        if let accom = accomAddr {
            // Center on accommodation
            geocoder.geocodeAddressString(accom) { placemarks, _ in
                if let loc = placemarks?.first?.location {
                    self.stayCoordinate = loc.coordinate
                    self.stayName = self.accommodationName
                    self.region = MKCoordinateRegion(
                        center: loc.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                    )
                    self.searchManager.searchRegion = self.region
                    self.searchManager.searchArea(region: self.region)
                } else if let dest = destAddr {
                    self.geocodeDestination(dest)
                }
            }
        } else if let dest = destAddr {
            geocodeDestination(dest)
        }
    }
    
    private func geocodeDestination(_ dest: String) {
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(dest) { placemarks, _ in
            if let loc = placemarks?.first?.location {
                self.region = MKCoordinateRegion(
                    center: loc.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
                self.searchManager.searchRegion = self.region
                self.searchManager.searchArea(region: self.region)
            }
        }
    }
    
    private func searchInArea() {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            searchManager.searchArea(region: region)
        } else {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = searchText
            request.resultTypes = .pointOfInterest
            request.region = region
            
            Task {
                let search = MKLocalSearch(request: request)
                if let response = try? await search.start() {
                    searchManager.results = response.mapItems
                }
            }
        }
    }
}
