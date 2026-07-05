//
//  EmailInputView.swift
//  TravelMemory
//
//  Manual email input view — allows pasting/typing email content
//  for testing the parser. This is also the fallback UI when the
//  Share Extension isn't available.
//

import SwiftUI
import SwiftData

struct EmailInputView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// When set, imported items go straight into this trip instead of
    /// matching/creating one by date.
    var targetTrip: Trip? = nil
    /// Called after a successful commit (e.g. so a presenting sheet can close too).
    var onCommitted: (() -> Void)? = nil

    @State private var subject = ""
    @State private var sender = ""
    @State private var emailBody = ""
    @State private var isProcessing = false
    @State private var parseResult: EmailParser.ParseResult?
    @State private var showingResult = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.voyagerBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: VoyagerSpacing.stackLarge) {
                        // Instructions
                        HStack(spacing: 12) {
                            Image(systemName: "envelope.open")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.voyagerPrimary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Paste Confirmation Email")
                                    .font(VoyagerFont.headlineMedium)
                                    .foregroundStyle(Color.voyagerOnSurface)
                                Text("Forward your booking email or paste the content below")
                                    .font(VoyagerFont.bodySmall)
                                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        
                        // Input fields
                        VStack(spacing: VoyagerSpacing.stackMedium) {
                            inputField(title: "FROM", placeholder: "sender@airline.com", text: $sender)
                            inputField(title: "SUBJECT", placeholder: "Your Flight Confirmation", text: $subject)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("EMAIL BODY")
                                    .font(VoyagerFont.labelCaps)
                                    .tracking(1.0)
                                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                                
                                TextEditor(text: $emailBody)
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
                            }
                        }
                        
                        // Sample button
                        Button {
                            loadSampleEmail()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                Text("LOAD SAMPLE EMAIL")
                            }
                            .font(VoyagerFont.labelCaps)
                            .tracking(0.6)
                            .foregroundStyle(Color.voyagerPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.voyagerPrimary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                            .overlay(
                                RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                                    .stroke(Color.voyagerPrimary.opacity(0.2), lineWidth: 1)
                            )
                        }
                        
                        // Parse button
                        Button {
                            parseEmail()
                        } label: {
                            HStack(spacing: 8) {
                                if isProcessing {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "wand.and.stars")
                                }
                                Text(isProcessing ? "PARSING..." : "PARSE EMAIL")
                            }
                        }
                        .buttonStyle(VoyagerPrimaryButtonStyle())
                        .disabled(emailBody.isEmpty || isProcessing)
                        .opacity(emailBody.isEmpty ? 0.5 : 1.0)
                    }
                    .padding(.horizontal, VoyagerSpacing.marginMain)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Add Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
            .sheet(isPresented: $showingResult) {
                if let result = parseResult {
                    ParseResultView(
                        result: result,
                        onAccept: {
                            // Nothing was persisted during parsing —
                            // commit only on explicit accept.
                            let service = EmailIngestionService(modelContext: modelContext)
                            service.commit(result, subject: subject, body: emailBody, sender: sender, into: targetTrip)
                            dismiss()
                            onCommitted?()
                        },
                        onDiscard: {
                            showingResult = false
                        }
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func inputField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(VoyagerFont.labelCaps)
                .tracking(1.0)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            
            TextField(placeholder, text: text)
                .font(VoyagerFont.bodySmall)
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
    
    private func parseEmail() {
        isProcessing = true

        Task {
            var result = await EmailIngestionService.parseContent(subject: subject, body: emailBody, sender: sender)
            if let trip = targetTrip {
                let duplicates = EmailIngestionService.duplicateDescriptions(in: result, against: trip)
                if !duplicates.isEmpty {
                    result.issues.append("Already in this trip (will be skipped): \(duplicates.joined(separator: ", "))")
                }
            }
            self.parseResult = result
            self.isProcessing = false
            self.showingResult = true
        }
    }
    
    private func loadSampleEmail() {
        sender = "noreply@lufthansa.com"
        subject = "Your Flight Confirmation - LH411"
        emailBody = """
        Dear Passenger,
        
        Your flight has been confirmed.
        
        Flight: Lufthansa LH411
        Date: Oct 12, 2025
        
        Departure: JFK (New York) at 18:30
        Arrival: MUC (Munich) at 08:15
        
        Gate: D4
        Seat: 14A
        
        Booking Reference: ABCX7K
        
        Hotel: Hotel Vier Jahreszeiten Kempinski
        Address: Maximilianstraße 17, 80539 München
        Check-in: Oct 12, 2025
        Check-out: Oct 18, 2025
        Confirmation: KMP884920
        
        Car Rental: Sixt Rent a Car
        Vehicle: BMW 5 Series or similar
        Pickup: Oct 12, 2025 at 15:30
        Dropoff: Oct 18, 2025 at 10:00
        Reservation: SX884920
        Pre-paid
        
        We wish you a pleasant journey!
        Lufthansa Customer Service
        """
    }
}

// MARK: - Parse Result View

struct ParseResultView: View {
    let result: EmailParser.ParseResult
    var onAccept: () -> Void
    var onDiscard: () -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.voyagerBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: VoyagerSpacing.stackLarge) {
                        // Confidence header
                        confidenceHeader
                        
                        // Parsed items
                        if !result.flights.isEmpty {
                            sectionHeader("Flights", icon: "airplane.departure")
                            ForEach(Array(result.flights.enumerated()), id: \.offset) { _, flight in
                                flightResultCard(flight)
                            }
                        }
                        
                        if !result.hotels.isEmpty {
                            sectionHeader("Hotels", icon: "bed.double")
                            ForEach(Array(result.hotels.enumerated()), id: \.offset) { _, hotel in
                                hotelResultCard(hotel)
                            }
                        }
                        
                        if !result.carRentals.isEmpty {
                            sectionHeader("Car Rentals", icon: "car")
                            ForEach(Array(result.carRentals.enumerated()), id: \.offset) { _, car in
                                carResultCard(car)
                            }
                        }

                        if !result.dining.isEmpty {
                            sectionHeader("Dining", icon: "fork.knife")
                            ForEach(Array(result.dining.enumerated()), id: \.offset) { _, dining in
                                diningResultCard(dining)
                            }
                        }

                        if !result.activities.isEmpty {
                            sectionHeader("Activities", icon: "figure.hiking")
                            ForEach(Array(result.activities.enumerated()), id: \.offset) { _, activity in
                                activityResultCard(activity)
                            }
                        }

                        // Issues
                        if !result.issues.isEmpty {
                            sectionHeader("Issues", icon: "exclamationmark.triangle")
                            ForEach(result.issues, id: \.self) { issue in
                                HStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.circle")
                                        .foregroundStyle(Color.voyagerTertiary)
                                    Text(issue)
                                        .font(VoyagerFont.bodySmall)
                                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.voyagerTertiary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                            }
                        }
                        
                        // Actions
                        VStack(spacing: 12) {
                            Button(action: onAccept) {
                                Text("ADD TO TRIP")
                            }
                            .buttonStyle(VoyagerPrimaryButtonStyle())
                            
                            Button(action: onDiscard) {
                                Text("DISCARD")
                                    .font(VoyagerFont.labelCaps)
                                    .tracking(0.6)
                                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, VoyagerSpacing.marginMain)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Parse Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Confidence Header
    
    private var confidenceHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.voyagerSurfaceContainerHighest, lineWidth: 4)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: result.overallConfidence)
                    .stroke(
                        confidenceColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(result.overallConfidence * 100))%")
                    .font(VoyagerFont.headlineMedium)
                    .foregroundStyle(confidenceColor)
            }
            
            Text(confidenceLabel)
                .font(VoyagerFont.labelCaps)
                .tracking(0.8)
                .foregroundStyle(confidenceColor)
        }
        .padding(.vertical, 16)
    }
    
    private var confidenceColor: Color {
        if result.overallConfidence >= 0.7 { return Color.voyagerPrimaryAccent }
        if result.overallConfidence >= 0.4 { return Color.voyagerTertiary }
        return Color.voyagerError
    }
    
    private var confidenceLabel: String {
        if result.overallConfidence >= 0.7 { return "HIGH CONFIDENCE" }
        if result.overallConfidence >= 0.4 { return "REVIEW RECOMMENDED" }
        return "LOW CONFIDENCE"
    }
    
    // MARK: - Section Header
    
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.voyagerPrimary)
            Text(title.uppercased())
                .font(VoyagerFont.labelCaps)
                .tracking(1.2)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            Spacer()
        }
        .padding(.top, 8)
    }
    
    // MARK: - Cards
    
    private func flightResultCard(_ flight: EmailParser.FlightParseData) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(flight.airline.isEmpty && flight.flightNumber.isEmpty ? "Unknown Flight" : "\(flight.airline) \(flight.flightNumber)")
                    .font(VoyagerFont.labelCaps)
                    .tracking(0.6)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                Spacer()
                confidencePill(flight.confidence)
            }
            
            HStack {
                VStack(alignment: .leading) {
                    Text(flight.departureAirport.isEmpty ? "—" : flight.departureAirport)
                        .font(VoyagerFont.headlineMedium)
                    Text(flight.departureCity)
                        .font(VoyagerFont.bodySmall)
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
                
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(Color.voyagerOutlineVariant)
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(flight.arrivalAirport.isEmpty ? "—" : flight.arrivalAirport)
                        .font(VoyagerFont.headlineMedium)
                    Text(flight.arrivalCity)
                        .font(VoyagerFont.bodySmall)
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
            .foregroundStyle(Color.voyagerOnSurface)
            
            if !flight.confirmationCode.isEmpty {
                HStack {
                    Text("Ref: \(flight.confirmationCode)")
                        .font(VoyagerFont.labelCaps)
                        .foregroundStyle(Color.voyagerPrimary)
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Color.voyagerCard)
        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerRadius.large)
                .stroke(Color.voyagerOutlineVariant.opacity(0.3), lineWidth: 0.5)
        )
    }
    
    private func hotelResultCard(_ hotel: EmailParser.HotelParseData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(hotel.hotelName.isEmpty ? "Unknown Hotel" : hotel.hotelName)
                    .font(VoyagerFont.bodyLarge)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.voyagerOnSurface)
                Spacer()
                confidencePill(hotel.confidence)
            }
            
            if let checkIn = hotel.checkIn {
                let fmt = DateFormatter()
                let _ = fmt.dateFormat = "MMM d, yyyy"
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                    Text("Check-in: \(fmt.string(from: checkIn))")
                }
                .font(VoyagerFont.bodySmall)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }
            
            if !hotel.confirmationCode.isEmpty {
                Text("Ref: \(hotel.confirmationCode)")
                    .font(VoyagerFont.labelCaps)
                    .foregroundStyle(Color.voyagerPrimary)
            }
        }
        .padding(16)
        .background(Color.voyagerCard)
        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerRadius.large)
                .stroke(Color.voyagerOutlineVariant.opacity(0.3), lineWidth: 0.5)
        )
    }
    
    private func carResultCard(_ car: EmailParser.CarRentalParseData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(car.company.isEmpty ? "Car Rental" : car.company)
                    .font(VoyagerFont.bodyLarge)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.voyagerOnSurface)
                Spacer()
                confidencePill(car.confidence)
            }
            
            if !car.vehicleType.isEmpty {
                Text(car.vehicleType)
                    .font(VoyagerFont.bodySmall)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }
            
            if car.isPrepaid {
                Text("PRE-PAID")
                    .font(VoyagerFont.labelCaps)
                    .tracking(0.4)
                    .foregroundStyle(Color.voyagerTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.voyagerTertiary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(16)
        .background(Color.voyagerCard)
        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerRadius.large)
                .stroke(Color.voyagerOutlineVariant.opacity(0.3), lineWidth: 0.5)
        )
    }
    
    private static let cardDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy 'at' HH:mm"
        return fmt
    }()

    private func diningResultCard(_ dining: EmailParser.DiningParseData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dining.restaurantName.isEmpty ? "Dining Reservation" : dining.restaurantName)
                    .font(VoyagerFont.bodyLarge)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.voyagerOnSurface)
                Spacer()
                confidencePill(dining.confidence)
            }

            if let time = dining.reservationTime {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                    Text(Self.cardDateFormatter.string(from: time))
                }
                .font(VoyagerFont.bodySmall)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }

            if !dining.address.isEmpty {
                Text(dining.address)
                    .font(VoyagerFont.bodySmall)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background(Color.voyagerCard)
        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerRadius.large)
                .stroke(Color.voyagerOutlineVariant.opacity(0.3), lineWidth: 0.5)
        )
    }

    private func activityResultCard(_ activity: EmailParser.ActivityParseData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(activity.activityName.isEmpty ? "Activity" : activity.activityName)
                    .font(VoyagerFont.bodyLarge)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.voyagerOnSurface)
                Spacer()
                confidencePill(activity.confidence)
            }

            if let start = activity.startTime {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                    Text(Self.cardDateFormatter.string(from: start))
                }
                .font(VoyagerFont.bodySmall)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }

            if !activity.location.isEmpty {
                Text(activity.location)
                    .font(VoyagerFont.bodySmall)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background(Color.voyagerCard)
        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerRadius.large)
                .stroke(Color.voyagerOutlineVariant.opacity(0.3), lineWidth: 0.5)
        )
    }

    private func confidencePill(_ confidence: Double) -> some View {
        Text("\(Int(confidence * 100))%")
            .font(VoyagerFont.labelCaps)
            .foregroundStyle(confidence >= 0.7 ? Color.voyagerPrimaryAccent : Color.voyagerTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                (confidence >= 0.7 ? Color.voyagerPrimaryAccent : Color.voyagerTertiary).opacity(0.1)
            )
            .clipShape(Capsule())
    }
}

struct EmailInputView_Previews: PreviewProvider {
    static var previews: some View {
        EmailInputView()
            .modelContainer(for: [Trip.self, FlightSegment.self, HotelBooking.self, CarRentalBooking.self, ParsedEmail.self], inMemory: true)
    }
}
