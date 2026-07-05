//
//  EditTripView.swift
//  TravelMemory
//
//  Create or edit a trip's basic properties.
//  Destination field uses MapKit autocomplete for cities/countries.
//

import SwiftUI
import SwiftData
import MapKit

// MARK: - Location Search Completer

@MainActor
class LocationSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query: String = "" {
        didSet {
            if query.isEmpty {
                suggestions = []
            } else {
                completer.queryFragment = query
            }
        }
    }
    @Published var suggestions: [MKLocalSearchCompletion] = []
    @Published var isSearching = false
    
    private let completer = MKLocalSearchCompleter()
    
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }
    
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            self.suggestions = Array(completer.results.prefix(5))
            self.isSearching = false
        }
    }
    
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.isSearching = false
        }
    }
}

// MARK: - Edit Trip View

struct EditTripView: View {
    enum Mode {
        case create
        case edit(Trip)
    }
    
    enum DatePickingPhase {
        case start, end
    }
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let mode: Mode
    
    @State private var name: String = ""
    @State private var destination: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(7 * 86400)
    @StateObject private var locationSearch = LocationSearchCompleter()
    @State private var showSuggestions = false
    @FocusState private var isDestinationFocused: Bool
    @State private var datePhase: DatePickingPhase = .start
    @State private var showCalendar = false
    
    private var isCreate: Bool {
        if case .create = mode { return true }
        return false
    }
    
    private var durationDays: Int {
        max(0, Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0)
    }
    
    private let displayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.voyagerBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: VoyagerSpacing.stackLarge) {
                        VoyagerFormField(title: "TRIP NAME", placeholder: "Munich Getaway", text: $name)
                        
                        // Destination with autocomplete
                        destinationField
                        
                        // Unified travel dates
                        travelDatesSection
                        
                        Button {
                            save()
                        } label: {
                            Text(isCreate ? "CREATE TRIP" : "SAVE CHANGES")
                        }
                        .buttonStyle(VoyagerPrimaryButtonStyle())
                        .disabled(name.isEmpty)
                        .opacity(name.isEmpty ? 0.5 : 1)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, VoyagerSpacing.marginMain)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(isCreate ? "New Trip" : "Edit Trip")
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
            if case .edit(let trip) = mode {
                name = trip.name
                destination = trip.destination
                startDate = trip.startDate
                endDate = trip.endDate
                locationSearch.query = trip.destination
            }
        }
    }
    
    // MARK: - Travel Dates Section
    
    private var travelDatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRAVEL DATES")
                .font(VoyagerFont.labelCaps)
                .tracking(1.0)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            
            // Date range summary bar
            HStack(spacing: 0) {
                // Start date button
                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        datePhase = .start
                        showCalendar = true
                    }
                } label: {
                    VStack(spacing: 3) {
                        Text("FROM")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(datePhase == .start && showCalendar ? Color.voyagerPrimaryAccent : Color.voyagerOnSurfaceVariant)
                        Text(displayFmt.string(from: startDate))
                            .font(VoyagerFont.bodySmall)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.voyagerOnSurface)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(datePhase == .start && showCalendar ? Color.voyagerPrimaryAccent.opacity(0.1) : .clear)
                    .overlay(alignment: .bottom) {
                        if datePhase == .start && showCalendar {
                            Rectangle()
                                .fill(Color.voyagerPrimaryAccent)
                                .frame(height: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                
                // Duration badge
                VStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.voyagerOutlineVariant)
                    Text("\(durationDays)d")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.voyagerPrimary)
                }
                .frame(width: 40)
                
                // End date button
                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        datePhase = .end
                        showCalendar = true
                    }
                } label: {
                    VStack(spacing: 3) {
                        Text("TO")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(datePhase == .end && showCalendar ? Color.voyagerPrimaryAccent : Color.voyagerOnSurfaceVariant)
                        Text(displayFmt.string(from: endDate))
                            .font(VoyagerFont.bodySmall)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.voyagerOnSurface)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(datePhase == .end && showCalendar ? Color.voyagerPrimaryAccent.opacity(0.1) : .clear)
                    .overlay(alignment: .bottom) {
                        if datePhase == .end && showCalendar {
                            Rectangle()
                                .fill(Color.voyagerPrimaryAccent)
                                .frame(height: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .background(Color.voyagerInputBackground)
            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                    .stroke(showCalendar ? Color.voyagerPrimary.opacity(0.4) : Color.voyagerInputBorder, lineWidth: 1)
            )
            
            // Graphical calendar
            if showCalendar {
                VStack(spacing: 8) {
                    // Phase indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.voyagerPrimaryAccent)
                            .frame(width: 6, height: 6)
                        Text(datePhase == .start ? "Tap departure date, then return date" : "Now tap your return date")
                            .font(VoyagerFont.bodySmall)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                        Spacer()
                        
                        // Collapse button
                        Button {
                            withAnimation(.easeOut(duration: 0.25)) {
                                showCalendar = false
                            }
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                                .padding(6)
                                .background(Color.voyagerSurfaceContainerHigh)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 4)
                    
                    calendarPicker
                }
                .padding(12)
                .background(Color.voyagerSurfaceContainerLow)
                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
                .overlay(
                    RoundedRectangle(cornerRadius: VoyagerRadius.large)
                        .stroke(Color.voyagerOutlineVariant.opacity(0.2), lineWidth: 0.5)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    // MARK: - Calendar Picker (Unified Range)
    
    @ViewBuilder
    private var calendarPicker: some View {
        DateRangeCalendar(
            startDate: $startDate,
            endDate: $endDate,
            onRangeSelected: {
                withAnimation(.easeOut(duration: 0.3).delay(0.3)) {
                    showCalendar = false
                }
            }
        )
    }
    
    // MARK: - Destination Field with Autocomplete
    
    private var destinationField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DESTINATION")
                .font(VoyagerFont.labelCaps)
                .tracking(1.0)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            
            TextField("Search city or country...", text: $destination)
                .font(VoyagerFont.bodyLarge)
                .foregroundStyle(Color.voyagerOnSurface)
                .padding(14)
                .background(Color.voyagerInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                        .stroke(showSuggestions && !locationSearch.suggestions.isEmpty
                                ? Color.voyagerPrimary.opacity(0.5)
                                : Color.voyagerInputBorder, lineWidth: 1)
                )
                .focused($isDestinationFocused)
                .onChange(of: destination) { _, newValue in
                    locationSearch.query = newValue
                    showSuggestions = !newValue.isEmpty
                }
                .onChange(of: isDestinationFocused) { _, focused in
                    if !focused {
                        // Delay hiding so tap on suggestion registers
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showSuggestions = false
                        }
                    } else {
                        showSuggestions = !destination.isEmpty
                    }
                }
            
            // Suggestions dropdown
            if showSuggestions && !locationSearch.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(locationSearch.suggestions, id: \.self) { suggestion in
                        Button {
                            selectSuggestion(suggestion)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.voyagerPrimary)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(suggestion.title)
                                        .font(VoyagerFont.bodySmall)
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.voyagerOnSurface)
                                    
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        
                        if suggestion != locationSearch.suggestions.last {
                            Divider()
                                .background(Color.voyagerOutlineVariant.opacity(0.3))
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private func selectSuggestion(_ suggestion: MKLocalSearchCompletion) {
        let title = suggestion.title
        let subtitle = suggestion.subtitle
        
        if subtitle.isEmpty {
            destination = title
        } else {
            destination = "\(title), \(subtitle)"
        }
        
        // Also auto-fill the trip name if empty
        if name.isEmpty {
            name = title
        }
        
        showSuggestions = false
        isDestinationFocused = false
    }
    
    // MARK: - Save
    
    private func save() {
        let savedTrip: Trip
        switch mode {
        case .create:
            let trip = Trip(name: name, destination: destination, startDate: startDate, endDate: endDate)
            modelContext.insert(trip)
            savedTrip = trip
        case .edit(let trip):
            trip.name = name
            trip.destination = destination
            trip.startDate = startDate
            trip.endDate = endDate
            savedTrip = trip
        }
        modelContext.saveOrLog()
        resolveTimeZone(for: savedTrip)
        dismiss()
    }

    /// Pins the trip's display zone to its destination's local zone
    private func resolveTimeZone(for trip: Trip) {
        guard !trip.destination.isEmpty else { return }
        CLGeocoder().geocodeAddressString(trip.destination) { placemarks, _ in
            guard let zone = placemarks?.first?.timeZone else { return }
            DispatchQueue.main.async {
                trip.timeZoneID = zone.identifier
                modelContext.saveOrLog()
            }
        }
    }
    
    // MARK: - Form Helpers
    
}

