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
    @State private var phone = ""
    @State private var websiteURL = ""
    @State private var itemStatus: ItineraryItemStatus = .booked
    @State private var costText = ""
    @State private var currencyText = ""
    @State private var notes = ""
    @State private var showDeleteConfirm = false
    @State private var showMapBrowser = false
    @State private var pasteStatus: String?
    
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

                        bookingHandoffRow
                        
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
                    TripNotifications.cancel(itemID: reservation.id)
                    modelContext.delete(reservation)
                    modelContext.saveOrLog()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showMapBrowser) {
                GoogleMapsBrowserView(
                    center: searchManager.searchRegion?.center,
                    destination: reservation.trip?.destination ?? "",
                    allowsShortlist: reservation.trip != nil,
                    onSelect: { place in
                        applySelection(place)
                    },
                    onShortlist: { place in
                        shortlistSelection(place)
                    }
                )
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
    
    private var nameSectionHeader: some View {
            HStack {
                Text("RESTAURANT")
                    .font(VoyagerFont.labelCaps)
                    .tracking(1.0)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                
                Spacer()
                
                HStack(spacing: 6) {
                    // Google Maps in-app: ratings, reviews, photos —
                    // selected places come straight back into this form
                    Button {
                        nameFieldFocus = false
                        showMapBrowser = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "star.circle")
                                .font(.system(size: 11))
                            Text("BROWSE WITH RATINGS")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.5)
                        }
                        .foregroundStyle(Color(hex: "#FFB868"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(hex: "#FFB868").opacity(0.1))
                        .clipShape(Capsule())
                    }

                    // Import a place copied from the Google Maps app.
                    // System PasteButton: reads the clipboard without the
                    // "Allow Paste?" alert that can deadlock inside sheets.
                    PasteButton(payloadType: String.self) { strings in
                        Task { @MainActor in
                            handlePastedLink(strings.first ?? "")
                        }
                    }
                    .labelStyle(.titleOnly)
                    .buttonBorderShape(.capsule)
                    .controlSize(.mini)
                    .tint(Color.voyagerPrimary.opacity(0.8))
                }
            }
    }

    private var restaurantNameSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            nameSectionHeader
            nameSearchField
            searchResultsDropdown
            statusFooter
        }
    }

    private var nameSearchField: some View {
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
    }

    @ViewBuilder
    private var searchResultsDropdown: some View {
        if !searchManager.results.isEmpty && isNameFieldFocused {
            VStack(spacing: 0) {
                ForEach(Array(searchManager.results.enumerated()), id: \.offset) { index, item in
                    Button {
                        selectRestaurant(item)
                        nameFieldFocus = false
                    } label: {
                        searchResultRow(item)
                    }
                    .buttonStyle(.plain)

                    if index < searchManager.results.count - 1 {
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
    }

    private func searchResultRow(_ item: MKMapItem) -> some View {
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

    @ViewBuilder
    private var statusFooter: some View {
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

        if let status = pasteStatus {
            let isProgress = status.hasPrefix("Reading")
            Text(status)
                .font(.system(size: 12))
                .foregroundStyle(isProgress ? Color.voyagerOnSurfaceVariant : Color.voyagerTertiary)
                .padding(.top, 2)
        }
    }

    // MARK: - Booking Handoff

    /// One-tap paths to actually book: call, website, or a Google search.
    @ViewBuilder
    private var bookingHandoffRow: some View {
        if !restaurantName.isEmpty {
            HStack(spacing: 10) {
                if !phone.isEmpty {
                    handoffButton(icon: "phone.fill", label: "CALL") {
                        let digits = phone.filter { !$0.isWhitespace }
                        if let url = URL(string: "tel:\(digits)") {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                if !websiteURL.isEmpty {
                    handoffButton(icon: "globe", label: "WEBSITE") {
                        if let url = URL(string: websiteURL) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                handoffButton(icon: "magnifyingglass", label: "BOOK ONLINE") {
                    let query = "\(restaurantName) \(reservation.trip?.destination ?? "") reservation"
                        .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "https://www.google.com/search?q=\(query)") {
                        UIApplication.shared.open(url)
                    }
                }

                Spacer()
            }
        }
    }

    private func handoffButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
            }
            .foregroundStyle(Color.voyagerPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.voyagerPrimary.opacity(0.1))
            .clipShape(Capsule())
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
    
    /// "650 m" / "2.4 km" style label
    static func distanceText(_ distance: CLLocationDistance) -> String {
        if distance < 1000 {
            return "\(Int((distance / 50).rounded() * 50)) m"
        }
        return String(format: "%.1f km", distance / 1000)
    }

    private func selectRestaurant(_ item: MKMapItem) {
        restaurantName = item.name ?? ""
        address = item.placemark.formattedAddress ?? ""
        phone = item.phoneNumber ?? ""
        websiteURL = item.url?.absoluteString ?? ""
        searchManager.clear()
    }

    // MARK: - Google Place Capture

    /// Fills the form from a place picked in the Google browser or a
    /// pasted link; address/phone/website resolve in the background.
    private func applySelection(_ selection: GooglePlaceSelection) {
        restaurantName = selection.name
        Task {
            let details = await resolveDetails(for: selection)
            if !details.address.isEmpty { address = details.address }
            if !details.phone.isEmpty { phone = details.phone }
            if !details.website.isEmpty { websiteURL = details.website }
        }
    }

    /// Saves a browsed place straight to the trip as an idea.
    private func shortlistSelection(_ selection: GooglePlaceSelection) {
        guard let trip = reservation.trip else { return }
        Task {
            let details = await resolveDetails(for: selection)
            let evening = Calendar.current.date(bySettingHour: 19, minute: 30, second: 0, of: trip.startDate) ?? trip.startDate
            let idea = DiningReservation(
                restaurantName: selection.name,
                address: details.address,
                reservationTime: evening,
                phone: details.phone,
                websiteURL: details.website
            )
            idea.status = .idea
            idea.trip = trip
            modelContext.insert(idea)
            modelContext.saveOrLog()
        }
    }

    /// Imports a "Share → Copy link" from the Google Maps app. The text
    /// arrives from PasteButton — no direct pasteboard access involved.
    private func handlePastedLink(_ text: String) {
        guard GoogleMapsLinkParser.isMapsLink(text) else {
            pasteStatus = "That wasn't a Google Maps link — use Share → Copy link in Google Maps."
            return
        }
        pasteStatus = "Reading link…"
        Task {
            if let place = await GoogleMapsLinkParser.expandAndParse(text) {
                applySelection(place)
                pasteStatus = nil
            } else {
                pasteStatus = "Couldn't read a place from that link."
            }
        }
    }

    /// Cross-resolves a Google place against MapKit (and reverse
    /// geocoding as fallback) to get a clean address, phone, and website.
    private func resolveDetails(for selection: GooglePlaceSelection) async -> (address: String, phone: String, website: String) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = selection.name
        if let coordinate = selection.coordinate {
            request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)
        } else if let region = searchManager.searchRegion {
            request.region = region
        }

        if let response = try? await MKLocalSearch(request: request).start(),
           !response.mapItems.isEmpty {
            let best: MKMapItem
            if let coordinate = selection.coordinate {
                let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                best = response.mapItems.min { a, b in
                    let aLoc = CLLocation(latitude: a.placemark.coordinate.latitude, longitude: a.placemark.coordinate.longitude)
                    let bLoc = CLLocation(latitude: b.placemark.coordinate.latitude, longitude: b.placemark.coordinate.longitude)
                    return target.distance(from: aLoc) < target.distance(from: bLoc)
                } ?? response.mapItems[0]

                // Accept only if it's plausibly the same place
                let bestLoc = CLLocation(latitude: best.placemark.coordinate.latitude, longitude: best.placemark.coordinate.longitude)
                if target.distance(from: bestLoc) <= 500 {
                    return (best.placemark.formattedAddress ?? "", best.phoneNumber ?? "", best.url?.absoluteString ?? "")
                }
            } else {
                best = response.mapItems[0]
                return (best.placemark.formattedAddress ?? "", best.phoneNumber ?? "", best.url?.absoluteString ?? "")
            }
        }

        // MapKit doesn't know it — at least get a street address
        if let coordinate = selection.coordinate {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
                return (placemark.formattedAddress ?? "", "", "")
            }
        }
        return ("", "", "")
    }

    private func loadValues() {
        restaurantName = reservation.restaurantName
        address = reservation.address
        reservationTime = reservation.reservationTime
        partySize = reservation.partySize
        confirmationCode = reservation.confirmationCode
        phone = reservation.phone
        websiteURL = reservation.websiteURL
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
        reservation.phone = phone
        reservation.websiteURL = websiteURL
        reservation.status = itemStatus
        reservation.cost = VoyagerCostField.parse(costText)
        reservation.currencyCode = currencyText.trimmingCharacters(in: .whitespaces).uppercased()
        reservation.notes = notes
        modelContext.saveOrLog()
        TripNotifications.resync(item: reservation, itemID: reservation.id)
        dismiss()
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
