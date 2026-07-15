//
//  EditHotelView.swift
//  TravelMemory
//
//  Edit accommodation with city-scoped MapKit search,
//  manual entry fallback, and Open in Maps.
//

import SwiftUI
import SwiftData
import MapKit

struct EditHotelView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var hotel: HotelBooking
    /// True when editing a just-created draft — dismissed without saving,
    /// the draft is deleted again so no empty rows linger in the timeline.
    var isNew: Bool = false
    @State private var isFinalized = false
    
    @State private var hotelName = ""
    @State private var address = ""
    @State private var checkInDate = Date()
    @State private var checkOutDate = Date()
    @State private var confirmationCode = ""
    @State private var itemStatus: ItineraryItemStatus = .booked
    @State private var costText = ""
    @State private var currencyText = ""
    @State private var roomType = ""
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var showDeleteConfirm = false
    
    // Search
    @State private var searchCity = ""
    @State private var searchName = ""
    @StateObject private var searcher = AccommodationSearcher()
    @State private var showResults = false
    @State private var isManualEntry = false
    @FocusState private var nameFocused: Bool
    
    /// Zone this event's times are entered and shown in
    private var eventZone: TimeZone {
        TimeZone(identifier: hotel.timeZoneID) ?? hotel.trip?.timeZone ?? .current
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.voyagerBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: VoyagerSpacing.stackLarge) {
                        // Step 1: City
                        searchSection
                        
                        // Filled accommodation card
                        if !hotelName.isEmpty && !nameFocused {
                            selectedCard
                        }
                        
                        VoyagerFormField(title: "ROOM TYPE", placeholder: "Deluxe King", text: $roomType)
                        VoyagerDateField(title: "CHECK-IN", date: $checkInDate, displayedComponents: .date, timeZone: eventZone)
                        VoyagerDateField(title: "CHECK-OUT", date: $checkOutDate, displayedComponents: .date, timeZone: eventZone)
                        VoyagerStatusPicker(status: $itemStatus)

                        VoyagerFormField(title: "CONFIRMATION CODE", placeholder: "KMP884920", text: $confirmationCode)

                        VoyagerCostField(costText: $costText, currencyCode: $currencyText)
                        
                        Button { save() } label: { Text("SAVE") }
                            .buttonStyle(VoyagerPrimaryButtonStyle())
                            .padding(.top, 8)
                        
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Text("DELETE ACCOMMODATION")
                                .font(VoyagerFont.labelCaps)
                                .tracking(0.6)
                                .foregroundStyle(Color.voyagerError)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }
                    .padding(.horizontal, VoyagerSpacing.marginMain)
                    .padding(.vertical, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(isNew ? "Add Accommodation" : "Edit Accommodation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
            .alert("Delete Accommodation?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    isFinalized = true
                    modelContext.delete(hotel)
                    modelContext.saveOrLog()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { loadValues() }
        .onDisappear {
            // Draft dismissed without saving — remove it again
            if isNew && !isFinalized {
                modelContext.delete(hotel)
                modelContext.saveOrLog()
            }
        }
    }
    
    // MARK: - Search Section
    
    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // City field
            VStack(alignment: .leading, spacing: 6) {
                Text("CITY / AREA")
                    .font(VoyagerFont.labelCaps)
                    .tracking(1.0)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                TextField("e.g. Munich, London, Paris...", text: $searchCity)
                    .font(VoyagerFont.bodyLarge)
                    .foregroundStyle(Color.voyagerOnSurface)
                    .padding(14)
                    .background(Color.voyagerInputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                            .stroke(Color.voyagerInputBorder, lineWidth: 1)
                    )
            }
            
            // Name search field
            VStack(alignment: .leading, spacing: 6) {
                Text("ACCOMMODATION NAME")
                    .font(VoyagerFont.labelCaps)
                    .tracking(1.0)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    TextField("Search hotel, apartment, B&B...", text: $searchName)
                        .font(VoyagerFont.bodyLarge)
                        .foregroundStyle(Color.voyagerOnSurface)
                        .focused($nameFocused)
                        .onChange(of: searchName) { _, newValue in
                            if newValue.count >= 2 {
                                let query = searchCity.isEmpty ? newValue : "\(newValue) \(searchCity)"
                                searcher.search(query: query)
                                showResults = true
                                isManualEntry = false
                            } else {
                                searcher.clear()
                                showResults = false
                            }
                        }
                        .onSubmit {
                            if searcher.results.isEmpty && !searchName.isEmpty {
                                isManualEntry = true
                                hotelName = searchName
                                showResults = false
                            }
                        }
                }
                .padding(14)
                .background(Color.voyagerInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                        .stroke(showResults ? Color.voyagerPrimary.opacity(0.5) : Color.voyagerInputBorder, lineWidth: 1)
                )
            }
            
            // Search button
            if !searchName.isEmpty && searchName.count >= 2 {
                Button {
                    let query = searchCity.isEmpty ? searchName : "\(searchName) \(searchCity)"
                    searcher.search(query: query)
                    showResults = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                        Text("SEARCH")
                            .font(VoyagerFont.labelCaps)
                            .tracking(0.4)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.voyagerPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                }
            }
            
            // Loading
            if searcher.isSearching {
                HStack(spacing: 8) {
                    ProgressView().tint(Color.voyagerPrimary).scaleEffect(0.7)
                    Text("Searching...").font(.system(size: 12)).foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
            
            // Results
            if showResults && !searcher.results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(searcher.results.enumerated()), id: \.offset) { index, item in
                        let name = item.name ?? "Unknown"
                        let addr = formatAddress(item.placemark)
                        
                        Button {
                            hotelName = name
                            address = addr
                            latitude = item.placemark.coordinate.latitude
                            longitude = item.placemark.coordinate.longitude
                            searchName = ""
                            showResults = false
                            nameFocused = false
                            isManualEntry = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "building.2.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.voyagerPrimary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(name)
                                        .font(VoyagerFont.bodySmallMedium)
                                        .foregroundStyle(Color.voyagerOnSurface)
                                        .lineLimit(1)
                                    Text(addr)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        
                        if index < searcher.results.count - 1 {
                            Divider().background(Color.voyagerOutlineVariant.opacity(0.3))
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
            
            // Not found — manual entry
            if showResults && searcher.results.isEmpty && !searcher.isSearching && searchName.count >= 2 {
                VStack(spacing: 10) {
                    Text("No results found")
                        .font(VoyagerFont.bodySmall)
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    Button {
                        isManualEntry = true
                        hotelName = searchName
                        showResults = false
                        nameFocused = false
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil")
                                .font(.system(size: 12))
                            Text("ENTER MANUALLY")
                                .font(VoyagerFont.labelCaps)
                                .tracking(0.4)
                        }
                        .foregroundStyle(Color.voyagerPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.voyagerPrimary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                    }
                }
                .padding(12)
                .background(Color.voyagerSurfaceContainerHigh)
                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
            }
            
            // Manual address entry
            if isManualEntry {
                VoyagerFormField(title: "ADDRESS (MANUAL)", placeholder: "Enter full address", text: $address)
            }
        }
    }
    
    // MARK: - Selected Card
    
    private var selectedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(hotelName)
                        .font(VoyagerFont.bodyLargeSemibold)
                        .foregroundStyle(Color.voyagerOnSurface)
                    if !address.isEmpty {
                        Text(address)
                            .font(VoyagerFont.bodySmall)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button {
                    hotelName = ""
                    address = ""
                    latitude = nil
                    longitude = nil
                    isManualEntry = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.voyagerOnSurfaceVariant.opacity(0.5))
                }
            }
            
            // Open in Maps
            if !address.isEmpty {
                Button {
                    openInMaps()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 13))
                        Text("OPEN IN MAPS")
                            .font(VoyagerFont.labelCaps)
                            .tracking(0.4)
                    }
                    .foregroundStyle(Color.voyagerPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.voyagerPrimary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                }
            }
        }
        .padding(14)
        .background(Color.voyagerPrimary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerRadius.large)
                .stroke(Color.voyagerPrimary.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Open in Maps
    
    private func openInMaps() {
        if let lat = latitude, let lng = longitude {
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            let placemark = MKPlacemark(coordinate: coord)
            let mapItem = MKMapItem(placemark: placemark)
            mapItem.name = hotelName
            mapItem.openInMaps(launchOptions: [MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coord)])
        } else {
            // Search by address
            let query = "\(hotelName) \(address)".trimmingCharacters(in: .whitespaces)
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "maps://?q=\(encoded)") {
                UIApplication.shared.open(url)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatAddress(_ placemark: CLPlacemark) -> String {
        [placemark.thoroughfare, placemark.subThoroughfare, placemark.locality,
         placemark.administrativeArea, placemark.country]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
    
    private func loadValues() {
        hotelName = hotel.hotelName
        address = hotel.address
        checkInDate = hotel.checkInDate
        checkOutDate = hotel.checkOutDate
        confirmationCode = hotel.confirmationCode
        itemStatus = hotel.status
        costText = VoyagerCostField.format(hotel.cost)
        currencyText = hotel.currencyCode
        roomType = hotel.roomType
        // Pre-fill city from trip destination
        if let trip = hotel.trip, searchCity.isEmpty {
            searchCity = trip.destination
        }
    }
    
    private func save() {
        isFinalized = true
        hotel.hotelName = hotelName
        hotel.address = address
        hotel.checkInDate = checkInDate
        hotel.checkOutDate = checkOutDate
        hotel.confirmationCode = confirmationCode.uppercased()
        hotel.status = itemStatus
        hotel.cost = VoyagerCostField.parse(costText)
        hotel.currencyCode = currencyText.trimmingCharacters(in: .whitespaces).uppercased()
        hotel.timeZoneID = eventZone.identifier
        hotel.roomType = roomType
        modelContext.saveOrLog()
        dismiss()
    }
    
    
}

// MARK: - Accommodation Searcher (MapKit)

@MainActor
class AccommodationSearcher: ObservableObject {
    @Published var results: [MKMapItem] = []
    @Published var isSearching = false
    private var task: Task<Void, Never>?
    
    func search(query: String) {
        task?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        isSearching = true
        task = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = .pointOfInterest
            do {
                let response = try await MKLocalSearch(request: request).start()
                if !Task.isCancelled {
                    self.results = Array(response.mapItems.prefix(6))
                }
            } catch {
                if !Task.isCancelled { self.results = [] }
            }
            self.isSearching = false
        }
    }
    
    func clear() {
        task?.cancel()
        results = []
    }
}

// MARK: - Paste Booking Sheet

struct PasteBookingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var pastedText: String
    let onParse: () -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.voyagerBackground.ignoresSafeArea()
                VStack(spacing: VoyagerSpacing.stackLarge) {
                    Text("Paste booking confirmation text below to extract details.")
                        .font(VoyagerFont.bodySmall)
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    
                    Button {
                        if let clip = UIPasteboard.general.string { pastedText = clip }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.clipboard")
                            Text("PASTE FROM CLIPBOARD")
                        }
                        .font(VoyagerFont.labelCaps)
                        .tracking(0.6)
                        .foregroundStyle(Color.voyagerPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.voyagerPrimary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                    }
                    
                    TextEditor(text: $pastedText)
                        .font(VoyagerFont.bodySmall)
                        .foregroundStyle(Color.voyagerOnSurface)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: 200)
                        .background(Color.voyagerInputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                        .overlay(
                            RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                                .stroke(Color.voyagerInputBorder, lineWidth: 1)
                        )
                    
                    Button { onParse(); dismiss() } label: { Text("EXTRACT DETAILS") }
                        .buttonStyle(VoyagerPrimaryButtonStyle())
                        .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                    Spacer()
                }
                .padding(.horizontal, VoyagerSpacing.marginMain)
                .padding(.top, 16)
            }
            .navigationTitle("Paste Booking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
