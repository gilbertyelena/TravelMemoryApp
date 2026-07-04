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
                            formField(title: "AIRLINE", placeholder: "Lufthansa", text: $airline)
                            formField(title: "FLIGHT #", placeholder: "LH411", text: $flightNumber)
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
                        dateField(title: "DEPARTURE", date: $departureTime)
                        dateField(title: "ARRIVAL", date: $arrivalTime)
                        
                        // Details
                        HStack(spacing: 12) {
                            formField(title: "GATE", placeholder: "D4", text: $gate)
                            formField(title: "SEAT", placeholder: "14A", text: $seat)
                            formField(title: "TERMINAL", placeholder: "1", text: $terminal)
                        }
                        
                        formField(title: "CONFIRMATION CODE", placeholder: "ABCX7K", text: $confirmationCode)
                        
                        Button { save() } label: { Text("SAVE") }
                            .buttonStyle(VoyagerPrimaryButtonStyle())
                            .padding(.top, 8)
                        
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Text("DELETE FLIGHT")
                                .font(VoyagerFont.labelCapsFallback)
                                .tracking(0.6)
                                .foregroundStyle(Color.voyagerError)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }
                    .padding(.horizontal, VoyagerSpacing.marginMain)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Edit Flight")
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
                    modelContext.delete(flight)
                    try? modelContext.save()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { loadValues() }
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
                .font(VoyagerFont.labelCapsFallback)
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
                            .font(VoyagerFont.bodyLargeFallback)
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
                        .font(VoyagerFont.bodyLargeFallback)
                        .foregroundStyle(Color.voyagerOnSurface)
                        .focused(isFocused)
                        .onChange(of: query.wrappedValue) { _, newValue in
                            let matches = AirportDatabase.search(newValue)
                            results.wrappedValue = matches
                            showResults.wrappedValue = !matches.isEmpty
                        }
                        .onChange(of: isFocused.wrappedValue) { _, focused in
                            if !focused {
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
                                icon: "airplane.circle.fill",
                                iconColor: Color.voyagerPrimary,
                                title: "\(airport.code) — \(airport.city)",
                                subtitle: airport.name
                            ) {
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
    }
    
    private func save() {
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
        try? modelContext.save()
        dismiss()
    }
    
    // MARK: - Form Helpers
    
    private func formField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(VoyagerFont.labelCapsFallback)
                .tracking(1.0)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            TextField(placeholder, text: text)
                .font(VoyagerFont.bodyLargeFallback)
                .foregroundStyle(Color.voyagerOnSurface)
                .padding(14)
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
