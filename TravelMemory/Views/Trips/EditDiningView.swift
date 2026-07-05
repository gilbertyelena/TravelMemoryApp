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

// MARK: - Edit Dining View

struct EditDiningView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var reservation: DiningReservation
    /// True when editing a just-created draft — dismissed without saving,
    /// the draft is deleted again so no empty rows linger in the timeline.
    var isNew: Bool = false
    @State private var isFinalized = false
    
    @State private var restaurantName = ""
    @State private var address = ""
    @State private var reservationTime = Date()
    @State private var partySize = 2
    @State private var confirmationCode = ""
    @State private var itemStatus: ItineraryItemStatus = .booked
    @State private var costText = ""
    @State private var currencyText = ""
    @State private var notes = ""
    @State private var showDeleteConfirm = false
    @State private var showMapBrowser = false
    
    @StateObject private var searchManager = PlaceSearchManager(
        pointOfInterestOnly: true,
        resultLimit: 6,
        pointOfInterestCategories: [.restaurant, .cafe, .bakery, .brewery, .winery]
    )
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
                        
                        VoyagerFormField(title: "ADDRESS", placeholder: "Full address", text: $address)
                        
                        VoyagerDateField(title: "RESERVATION TIME", date: $reservationTime)
                        
                        // Party size stepper
                        partySizeSection
                        
                        VoyagerStatusPicker(status: $itemStatus)

                        VoyagerFormField(title: "CONFIRMATION CODE", placeholder: "Optional", text: $confirmationCode)

                        VoyagerCostField(costText: $costText, currencyCode: $currencyText)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOTES")
                                .font(VoyagerFont.labelCaps)
                                .tracking(1.0)
                                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                            TextField("Dietary requirements, special requests...", text: $notes, axis: .vertical)
                                .font(VoyagerFont.bodyLarge)
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
                                .font(VoyagerFont.labelCaps)
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
            .navigationTitle(isNew ? "Add Reservation" : "Edit Reservation")
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
                    isFinalized = true
                    modelContext.delete(reservation)
                    modelContext.saveOrLog()
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
        .onDisappear {
            // Draft dismissed without saving — remove it again
            if isNew && !isFinalized {
                modelContext.delete(reservation)
                modelContext.saveOrLog()
            }
        }
    }
    
    // MARK: - Restaurant Name with Search
    
    private var restaurantNameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RESTAURANT")
                    .font(VoyagerFont.labelCaps)
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
                .font(VoyagerFont.bodyLarge)
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

                                // Distance from the stay / trip center
                                if let distance = searchManager.distance(to: item) {
                                    Text(Self.distanceText(distance))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.voyagerPrimary)
                                }
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
                .font(VoyagerFont.labelCaps)
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
                    .font(VoyagerFont.bodySmall)
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

    /// "650 m" / "2.4 km" style label
    static func distanceText(_ distance: CLLocationDistance) -> String {
        if distance < 1000 {
            return "\(Int((distance / 50).rounded() * 50)) m"
        }
        return String(format: "%.1f km", distance / 1000)
    }
    
    private func loadValues() {
        restaurantName = reservation.restaurantName
        address = reservation.address
        reservationTime = reservation.reservationTime
        partySize = reservation.partySize
        confirmationCode = reservation.confirmationCode
        itemStatus = reservation.status
        costText = VoyagerCostField.format(reservation.cost)
        currencyText = reservation.currencyCode
        notes = reservation.notes
    }
    
    private func save() {
        isFinalized = true
        reservation.restaurantName = restaurantName
        reservation.address = address
        reservation.reservationTime = reservationTime
        reservation.partySize = partySize
        reservation.confirmationCode = confirmationCode
        reservation.status = itemStatus
        reservation.cost = VoyagerCostField.parse(costText)
        reservation.currencyCode = currencyText.trimmingCharacters(in: .whitespaces).uppercased()
        reservation.notes = notes
        modelContext.saveOrLog()
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
    @ObservedObject var searchManager: PlaceSearchManager
    let onSelect: (MKMapItem) -> Void
    
    @Environment(\.dismiss) private var dismiss
    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 38.72, longitude: -9.14),
        span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
    )
    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)
    /// The currently visible region, tracked for "search this area"
    @State private var region = Self.defaultRegion
    @State private var selectedItem: MKMapItem?
    @State private var hasGeocoded = false
    @State private var searchText = ""
    @State private var stayCoordinate: CLLocationCoordinate2D?
    @State private var stayName: String = ""
    /// Where the last area search ran — panning far from it re-searches.
    @State private var lastSearchedCenter: CLLocationCoordinate2D?
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $cameraPosition) {
                    ForEach(allAnnotations) { ann in
                        Annotation(ann.isStay ? ann.name : "", coordinate: ann.coordinate) {
                            annotationContent(ann)
                        }
                    }
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    region = context.region
                    autoSearchIfPannedFar()
                }
                .ignoresSafeArea(edges: .bottom)

                // Search bar overlay
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                        TextField("Search restaurants...", text: $searchText)
                            .font(VoyagerFont.bodySmall)
                            .foregroundStyle(Color.voyagerOnSurface)
                            .onSubmit {
                                searchInArea()
                            }
                        
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchManager.searchArea(region: region, query: "restaurant")
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
                        searchManager.searchArea(region: region, query: "restaurant")
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
    
    @ViewBuilder
    private func annotationContent(_ ann: MapPinAnnotation) -> some View {
        if ann.isStay {
            // Accommodation pin
            ZStack {
                Circle()
                    .fill(Color.voyagerTertiary)
                    .frame(width: 36, height: 36)
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
            }
            .shadow(color: Color.voyagerTertiary.opacity(0.5), radius: 6, y: 2)
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

    private func selectedRestaurantCard(_ item: MKMapItem) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name ?? "Restaurant")
                        .font(VoyagerFont.bodyLarge)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.voyagerOnSurface)
                    
                    if let addr = item.placemark.formattedAddress {
                        Text(addr)
                            .font(VoyagerFont.bodySmall)
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
                    self.cameraPosition = .region(self.region)
                    self.lastSearchedCenter = self.region.center
                    self.searchManager.searchRegion = self.region
                    self.searchManager.searchArea(region: self.region, query: "restaurant")
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
                self.cameraPosition = .region(self.region)
                self.lastSearchedCenter = self.region.center
                self.searchManager.searchRegion = self.region
                self.searchManager.searchArea(region: self.region, query: "restaurant")
            }
        }
    }
    
    private func searchInArea() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        lastSearchedCenter = region.center
        searchManager.searchArea(region: region, query: query.isEmpty ? "restaurant" : query)
    }

    /// Re-run the area search automatically once the camera settles more
    /// than half a screen away from the last searched spot.
    private func autoSearchIfPannedFar() {
        guard let last = lastSearchedCenter else { return }
        let lastLocation = CLLocation(latitude: last.latitude, longitude: last.longitude)
        let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let visibleHeightMeters = region.span.latitudeDelta * 111_000
        if center.distance(from: lastLocation) > visibleHeightMeters * 0.5 {
            searchInArea()
        }
    }
}
