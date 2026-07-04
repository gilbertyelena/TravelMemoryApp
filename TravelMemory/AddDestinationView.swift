//
//  AddDestinationView.swift
//  TravelMemory
//
//  Created by Yelena Gilbert on 28/04/2026.
//

import SwiftUI
import SwiftData
import MapKit
import PhotosUI

struct AddDestinationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var city = ""
    @State private var country = ""
    @State private var dateFrom = Date()
    @State private var dateTo = Date()
    @State private var hotelName = ""
    @State private var hotelLink = ""
    @State private var notes = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var coverPhotoData: Data?
    
    // City search & validation
    @State private var citySearchText = ""
    @State private var citySearchResults: [MKMapItem] = []
    @State private var isSearchingCity = false
    @State private var cityIsValidated = false
    @State private var showCitySuggestions = false
    
    // Map
    @State private var mapPosition = MapCameraPosition.automatic
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    
    // Optional: editing an existing destination
    var existingDestination: Destination?
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Cover Photo
                Section {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        if let coverPhotoData, let uiImage = UIImage(data: coverPhotoData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.white)
                                        .padding(8)
                                }
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        LinearGradient(
                                            colors: [.orange.opacity(0.2), .pink.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(height: 160)
                                
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.largeTitle)
                                        .foregroundStyle(.orange)
                                    Text("Add Cover Photo")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                
                // MARK: - City Search
                Section {
                    // City search field
                    HStack {
                        Image(systemName: "building.2")
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                        
                        TextField("Search for a city", text: $citySearchText)
                            .autocorrectionDisabled()
                            .onChange(of: citySearchText) { _ in
                                // Reset validation when user edits
                                if cityIsValidated && citySearchText != city {
                                    cityIsValidated = false
                                    country = ""
                                    selectedCoordinate = nil
                                }
                                // Debounced search
                                searchCityDebounced()
                            }
                            .onSubmit {
                                searchCity()
                            }
                        
                        if isSearchingCity {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if cityIsValidated {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    
                    // Validated city & country display
                    if cityIsValidated {
                        HStack {
                            Image(systemName: "flag")
                                .foregroundStyle(.orange)
                                .frame(width: 24)
                            Text(country)
                                .foregroundStyle(.primary)
                            Spacer()
                            // Allow clearing to re-search
                            Button {
                                clearCitySelection()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Search results / suggestions
                    if showCitySuggestions && !citySearchResults.isEmpty {
                        ForEach(citySearchResults, id: \.self) { item in
                            Button {
                                selectCity(item)
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(.orange.opacity(0.15))
                                            .frame(width: 36, height: 36)
                                        Image(systemName: "mappin")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(cityDisplayName(for: item))
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)
                                        Text(citySubtitle(for: item))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Destination")
                } footer: {
                    if !cityIsValidated && !citySearchText.isEmpty && !showCitySuggestions {
                        Text("Tap return or wait for suggestions to validate the city")
                            .foregroundStyle(.orange)
                    }
                }
                
                // MARK: - Map Preview
                if selectedCoordinate != nil {
                    Section("Location") {
                        Map(position: $mapPosition) {
                            if let coord = selectedCoordinate {
                                Marker(city.isEmpty ? "Location" : city, coordinate: coord)
                                    .tint(.orange)
                            }
                        }
                        .mapStyle(.standard(elevation: .realistic))
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                
                // MARK: - Dates
                Section("Travel Dates") {
                    DatePicker("From", selection: $dateFrom, displayedComponents: .date)
                        .tint(.orange)
                    DatePicker("To", selection: $dateTo, in: dateFrom..., displayedComponents: .date)
                        .tint(.orange)
                }
                
                // MARK: - Hotel
                Section("Accommodation") {
                    HStack {
                        Image(systemName: "bed.double")
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                        TextField("Hotel name", text: $hotelName)
                    }
                    HStack {
                        Image(systemName: "link")
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                        TextField("Booking link (optional)", text: $hotelLink)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                    }
                }
                
                // MARK: - Notes
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle(existingDestination == nil ? "New Trip" : "Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .tint(.orange)
                        .disabled(!cityIsValidated)
                }
            }
            .onChange(of: selectedPhoto) { _ in
                loadPhoto()
            }
            .onAppear {
                if let dest = existingDestination {
                    city = dest.city
                    country = dest.country
                    citySearchText = dest.city
                    cityIsValidated = true
                    dateFrom = dest.dateFrom
                    dateTo = dest.dateTo
                    hotelName = dest.hotelName
                    hotelLink = dest.hotelLink
                    notes = dest.notes
                    coverPhotoData = dest.coverPhotoData
                    if dest.latitude != 0 || dest.longitude != 0 {
                        selectedCoordinate = dest.coordinate
                        mapPosition = .region(MKCoordinateRegion(
                            center: dest.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                        ))
                    }
                }
            }
        }
    }
    
    // MARK: - City Search
    
    @State private var searchTask: Task<Void, Never>?
    
    private func searchCityDebounced() {
        searchTask?.cancel()
        
        guard citySearchText.count >= 2 else {
            citySearchResults = []
            showCitySuggestions = false
            return
        }
        
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await performCitySearch()
        }
    }
    
    private func searchCity() {
        guard citySearchText.count >= 2 else { return }
        Task {
            await performCitySearch()
        }
    }
    
    @MainActor
    private func performCitySearch() async {
        isSearchingCity = true
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = citySearchText
        request.resultTypes = .address
        
        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            
            // Filter to results that look like cities (have locality)
            let cityResults = response.mapItems.filter { item in
                item.placemark.locality != nil || item.placemark.name != nil
            }
            
            citySearchResults = Array(cityResults.prefix(6))
            showCitySuggestions = !citySearchResults.isEmpty
        } catch {
            citySearchResults = []
            showCitySuggestions = false
        }
        
        isSearchingCity = false
    }
    
    private func selectCity(_ item: MKMapItem) {
        let placemark = item.placemark
        
        // Set city name
        city = placemark.locality ?? placemark.name ?? citySearchText
        citySearchText = city
        
        // Set country
        country = placemark.country ?? ""
        
        // If there's a sub-administrative area or state, include it for clarity
        if let admin = placemark.administrativeArea, !admin.isEmpty {
            if country.isEmpty {
                country = admin
            }
        }
        
        // Set coordinates
        let coord = placemark.coordinate
        selectedCoordinate = coord
        mapPosition = .region(MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        ))
        
        // Mark as validated
        cityIsValidated = true
        showCitySuggestions = false
        citySearchResults = []
    }
    
    private func clearCitySelection() {
        city = ""
        country = ""
        citySearchText = ""
        cityIsValidated = false
        selectedCoordinate = nil
        mapPosition = .automatic
        citySearchResults = []
        showCitySuggestions = false
    }
    
    // MARK: - Helpers
    
    private func cityDisplayName(for item: MKMapItem) -> String {
        let placemark = item.placemark
        return placemark.locality ?? placemark.name ?? "Unknown"
    }
    
    private func citySubtitle(for item: MKMapItem) -> String {
        let placemark = item.placemark
        var parts: [String] = []
        if let admin = placemark.administrativeArea {
            parts.append(admin)
        }
        if let countryName = placemark.country {
            parts.append(countryName)
        }
        return parts.joined(separator: ", ")
    }
    
    // MARK: - Photo
    
    private func loadPhoto() {
        Task {
            if let data = try? await selectedPhoto?.loadTransferable(type: Data.self) {
                coverPhotoData = data
            }
        }
    }
    
    // MARK: - Save
    
    private func save() {
        if let dest = existingDestination {
            dest.city = city
            dest.country = country
            dest.dateFrom = dateFrom
            dest.dateTo = dateTo
            dest.hotelName = hotelName
            dest.hotelLink = hotelLink
            dest.notes = notes
            dest.coverPhotoData = coverPhotoData
            if let coord = selectedCoordinate {
                dest.latitude = coord.latitude
                dest.longitude = coord.longitude
            }
        } else {
            let destination = Destination(
                city: city,
                country: country,
                dateFrom: dateFrom,
                dateTo: dateTo,
                latitude: selectedCoordinate?.latitude ?? 0,
                longitude: selectedCoordinate?.longitude ?? 0,
                coverPhotoData: coverPhotoData,
                hotelName: hotelName,
                hotelLink: hotelLink,
                notes: notes
            )
            modelContext.insert(destination)
        }
        dismiss()
    }
}

struct AddDestinationView_Previews: PreviewProvider {
    static var previews: some View {
        AddDestinationView()
            .modelContainer(for: [Destination.self, Memory.self, Photo.self], inMemory: true)
    }
}
