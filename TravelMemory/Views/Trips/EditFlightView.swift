//
//  EditFlightView.swift
//  TravelMemory
//
//  Edit a flight segment with airport search by city/code.
//

import SwiftUI
import SwiftData
import MapKit

struct EditFlightView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var flight: FlightSegment
    /// True when editing a just-created draft — dismissed without saving,
    /// the draft is deleted again so no empty rows linger in the timeline.
    var isNew: Bool = false
    /// Called with the pre-filled return segment after "Save & Add Return".
    var onSaveAndAddReturn: ((FlightSegment) -> Void)? = nil

    @State private var isFinalized = false
    @State private var airline: String = ""
    @State private var flightNumber: String = ""
    @State private var departureAirport: String = ""
    @State private var departureCity: String = ""
    @State private var arrivalAirport: String = ""
    @State private var arrivalCity: String = ""
    @State private var departureTime: Date = Date()
    @State private var arrivalTime: Date = Date()
    @State private var gate: String = ""
    @State private var seat: String = ""
    @State private var terminal: String = ""
    @State private var confirmationCode: String = ""
    @State private var itemStatus: ItineraryItemStatus = .booked
    @State private var costText = ""
    @State private var currencyText = ""
    @State private var showDeleteConfirm = false
    
    // Search state
    @State private var departureQuery: String = ""
    @State private var arrivalQuery: String = ""
    @State private var departureResults: [(code: String, city: String, name: String)] = []
    @State private var arrivalResults: [(code: String, city: String, name: String)] = []
    @State private var showDepResults = false
    @State private var showArrResults = false
    @FocusState private var depFocused: Bool
    @FocusState private var arrFocused: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.voyagerBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: VoyagerSpacing.stackLarge) {
                        // Airline & Flight
                        HStack(spacing: 12) {
                            VoyagerFormField(title: "AIRLINE", placeholder: "Lufthansa", text: $airline)
                            VoyagerFormField(title: "FLIGHT #", placeholder: "LH411", text: $flightNumber)
                        }
                        
                        // Departure search
                        airportSearchField(
                            title: "FROM",
                            query: $departureQuery,
                            results: $departureResults,
                            showResults: $showDepResults,
                            isFocused: $depFocused,
                            airportCode: departureAirport,
                            cityName: departureCity,
                            onSelect: { code, city in
                                departureAirport = code
                                departureCity = city
                                departureQuery = ""
                                showDepResults = false
                                depFocused = false
                            }
                        )
                        
                        // Arrival search
                        airportSearchField(
                            title: "TO",
                            query: $arrivalQuery,
                            results: $arrivalResults,
                            showResults: $showArrResults,
                            isFocused: $arrFocused,
                            airportCode: arrivalAirport,
                            cityName: arrivalCity,
                            onSelect: { code, city in
                                arrivalAirport = code
                                arrivalCity = city
                                arrivalQuery = ""
                                showArrResults = false
                                arrFocused = false
                            }
                        )
                        
                        // Times
                        VoyagerDateField(title: "DEPARTURE", date: $departureTime)
                        VoyagerDateField(title: "ARRIVAL", date: $arrivalTime)
                        
                        // Details
                        HStack(spacing: 12) {
                            VoyagerFormField(title: "GATE", placeholder: "D4", text: $gate)
                            VoyagerFormField(title: "SEAT", placeholder: "14A", text: $seat)
                            VoyagerFormField(title: "TERMINAL", placeholder: "1", text: $terminal)
                        }
                        
                        VoyagerStatusPicker(status: $itemStatus)

                        VoyagerFormField(title: "CONFIRMATION CODE", placeholder: "ABCX7K", text: $confirmationCode)

                        VoyagerCostField(costText: $costText, currencyCode: $currencyText)
                        
                        Button { save() } label: { Text("SAVE") }
                            .buttonStyle(VoyagerPrimaryButtonStyle())
                            .padding(.top, 8)

                        // Round trips are the common case — offer to
                        // create the reverse leg in one tap.
                        if onSaveAndAddReturn != nil && !departureAirport.isEmpty && !arrivalAirport.isEmpty {
                            Button { saveAndAddReturn() } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.uturn.left")
                                    Text("SAVE & ADD RETURN FLIGHT")
                                }
                                .font(VoyagerFont.labelCaps)
                                .tracking(0.6)
                                .foregroundStyle(Color.voyagerPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.voyagerPrimary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                            }
                        }

                        if !isNew {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Text("DELETE FLIGHT")
                                    .font(VoyagerFont.labelCaps)
                                    .tracking(0.6)
                                    .foregroundStyle(Color.voyagerError)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                        }
                    }
                    .padding(.horizontal, VoyagerSpacing.marginMain)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle(isNew ? "Add Flight" : "Edit Flight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
            .alert("Delete Flight?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    isFinalized = true
                    TripNotifications.cancel(itemID: flight.id)
                    modelContext.delete(flight)
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
                modelContext.delete(flight)
                modelContext.saveOrLog()
            }
        }
    }
    
    // MARK: - Airport Search Field
    
    private func airportSearchField(
        title: String,
        query: Binding<String>,
        results: Binding<[(code: String, city: String, name: String)]>,
        showResults: Binding<Bool>,
        isFocused: FocusState<Bool>.Binding,
        airportCode: String,
        cityName: String,
        onSelect: @escaping (String, String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(VoyagerFont.labelCaps)
                .tracking(1.0)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            
            // Selected airport display
            if !airportCode.isEmpty {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Text(airportCode)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.voyagerPrimary)
                        Text(cityName)
                            .font(VoyagerFont.bodyLarge)
                            .foregroundStyle(Color.voyagerOnSurface)
                    }
                    
                    Spacer()
                    
                    Button {
                        // Allow changing
                        if title == "FROM" {
                            departureAirport = ""
                            departureCity = ""
                        } else {
                            arrivalAirport = ""
                            arrivalCity = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.voyagerOnSurfaceVariant.opacity(0.5))
                    }
                }
                .padding(14)
                .background(Color.voyagerPrimary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                        .stroke(Color.voyagerPrimary.opacity(0.2), lineWidth: 1)
                )
            } else {
                // Search field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    
                    TextField("Search city or airport code...", text: query)
                        .font(VoyagerFont.bodyLarge)
                        .foregroundStyle(Color.voyagerOnSurface)
                        .focused(isFocused)
                        .onChange(of: query.wrappedValue) { _, newValue in
                            let matches = airportSuggestions(for: newValue)
                            results.wrappedValue = matches
                            showResults.wrappedValue = !matches.isEmpty
                        }
                        .onChange(of: isFocused.wrappedValue) { _, focused in
                            if focused {
                                // Show recent picks before the user types
                                let matches = airportSuggestions(for: query.wrappedValue)
                                results.wrappedValue = matches
                                showResults.wrappedValue = !matches.isEmpty
                            } else {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    showResults.wrappedValue = false
                                }
                            }
                        }
                }
                .padding(14)
                .background(Color.voyagerInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                        .stroke(showResults.wrappedValue ? Color.voyagerPrimary.opacity(0.5) : Color.voyagerInputBorder, lineWidth: 1)
                )
                
                // Results dropdown
                if showResults.wrappedValue {
                    VStack(spacing: 0) {
                        ForEach(Array(results.wrappedValue.enumerated()), id: \.offset) { index, airport in
                            SearchSuggestionRow(
                                icon: query.wrappedValue.isEmpty ? "clock.arrow.circlepath" : "airplane.circle.fill",
                                iconColor: Color.voyagerPrimary,
                                title: "\(airport.code) — \(airport.city)",
                                subtitle: airport.name
                            ) {
                                AirportDatabase.recordRecent(code: airport.code)
                                onSelect(airport.code, airport.city)
                            }
                            
                            if index < results.wrappedValue.count - 1 {
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
            }
        }
    }
    
    /// Ranked matches for a query; recent picks when the query is empty.
    private func airportSuggestions(for query: String) -> [(code: String, city: String, name: String)] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? AirportDatabase.recents() : AirportDatabase.search(trimmed)
    }

    // MARK: - Load / Save

    private func loadValues() {
        airline = flight.airline
        flightNumber = flight.flightNumber
        departureAirport = flight.departureAirport
        departureCity = flight.departureCity
        arrivalAirport = flight.arrivalAirport
        arrivalCity = flight.arrivalCity
        departureTime = flight.departureTime
        arrivalTime = flight.arrivalTime
        gate = flight.gate
        seat = flight.seat
        terminal = flight.terminal
        confirmationCode = flight.confirmationCode
        itemStatus = flight.status
        costText = VoyagerCostField.format(flight.cost)
        currencyText = flight.currencyCode
    }
    
    private func applyChanges() {
        flight.airline = airline
        flight.flightNumber = flightNumber
        flight.departureAirport = departureAirport.uppercased()
        flight.departureCity = departureCity
        flight.arrivalAirport = arrivalAirport.uppercased()
        flight.arrivalCity = arrivalCity
        flight.departureTime = departureTime
        flight.arrivalTime = arrivalTime
        flight.gate = gate
        flight.seat = seat
        flight.terminal = terminal
        flight.confirmationCode = confirmationCode.uppercased()
        flight.status = itemStatus
        flight.cost = VoyagerCostField.parse(costText)
        flight.currencyCode = currencyText.trimmingCharacters(in: .whitespaces).uppercased()
        modelContext.saveOrLog()
        TripNotifications.resync(item: flight, itemID: flight.id)
        isFinalized = true
    }

    private func save() {
        applyChanges()
        dismiss()
    }

    /// Saves the current flight, then hands a pre-filled reverse leg
    /// back to the presenter to edit.
    private func saveAndAddReturn() {
        applyChanges()

        let flightDuration = arrivalTime.timeIntervalSince(departureTime)
        // Best guess for the return date: the trip's end date if it lies
        // after this leg's arrival, otherwise later the same day.
        let returnDeparture: Date
        if let tripEnd = flight.trip?.endDate, tripEnd > arrivalTime {
            returnDeparture = tripEnd
        } else {
            returnDeparture = arrivalTime.addingTimeInterval(4 * 3600)
        }

        let returnFlight = FlightSegment(
            airline: airline,
            flightNumber: "",
            departureAirport: arrivalAirport.uppercased(),
            departureCity: arrivalCity,
            arrivalAirport: departureAirport.uppercased(),
            arrivalCity: departureCity,
            departureTime: returnDeparture,
            arrivalTime: returnDeparture.addingTimeInterval(max(flightDuration, 0)),
            confirmationCode: confirmationCode.uppercased()
        )
        returnFlight.trip = flight.trip
        modelContext.insert(returnFlight)
        modelContext.saveOrLog()

        dismiss()
        onSaveAndAddReturn?(returnFlight)
    }
}
