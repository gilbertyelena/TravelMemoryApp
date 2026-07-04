//
//  EmailIngestionService.swift
//  TravelMemory
//
//  Service layer that receives shared email content,
//  runs the parser, creates SwiftData models, and manages
//  the review workflow.
//

import Foundation
import SwiftData

@MainActor
final class EmailIngestionService: ObservableObject {
    private let modelContext: ModelContext
    
    @Published var lastParseResult: EmailParser.ParseResult?
    @Published var isProcessing = false
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Ingest raw email content — called from Share Extension or manual paste
    func ingestEmail(subject: String, body: String, sender: String) async -> Trip? {
        isProcessing = true
        defer { isProcessing = false }
        
        // Parse the email
        let result = EmailParser.parse(subject: subject, body: body, sender: sender)
        lastParseResult = result
        
        // Determine if this belongs to an existing trip or needs a new one
        let trip = findOrCreateTrip(for: result)
        
        // Create flight segments
        for flightData in result.flights {
            let flight = FlightSegment(
                airline: flightData.airline,
                flightNumber: flightData.flightNumber,
                departureAirport: flightData.departureAirport,
                departureCity: flightData.departureCity,
                arrivalAirport: flightData.arrivalAirport,
                arrivalCity: flightData.arrivalCity,
                departureTime: flightData.departureTime ?? .now,
                arrivalTime: flightData.arrivalTime ?? .now,
                gate: flightData.gate,
                seat: flightData.seat,
                confirmationCode: flightData.confirmationCode,
                confidence: flightData.confidence
            )
            trip.flights.append(flight)
            modelContext.insert(flight)
        }
        
        // Create hotel bookings
        for hotelData in result.hotels {
            let hotel = HotelBooking(
                hotelName: hotelData.hotelName,
                address: hotelData.address,
                checkInDate: hotelData.checkIn ?? .now,
                checkOutDate: hotelData.checkOut ?? .now,
                confirmationCode: hotelData.confirmationCode,
                confidence: hotelData.confidence
            )
            trip.hotels.append(hotel)
            modelContext.insert(hotel)
        }
        
        // Create car rental bookings
        for carData in result.carRentals {
            let car = CarRentalBooking(
                company: carData.company,
                vehicleType: carData.vehicleType,
                pickupTime: carData.pickupTime ?? .now,
                dropoffTime: carData.dropoffTime ?? .now,
                pickupLocation: carData.pickupLocation,
                confirmationCode: carData.confirmationCode,
                isPrepaid: carData.isPrepaid,
                confidence: carData.confidence
            )
            trip.carRentals.append(car)
            modelContext.insert(car)
        }
        
        // Create parsed email record
        let parsedEmail = ParsedEmail(
            subject: subject,
            senderEmail: sender,
            rawBody: body,
            receivedAt: .now,
            statusRaw: result.overallConfidence >= 0.7 ? "accepted" : "needsReview",
            overallConfidence: result.overallConfidence,
            issues: result.issues
        )
        trip.parsedEmails.append(parsedEmail)
        modelContext.insert(parsedEmail)
        
        // Save
        try? modelContext.save()
        
        return trip
    }
    
    /// Find a trip that matches the parsed dates or create a new one
    private func findOrCreateTrip(for result: EmailParser.ParseResult) -> Trip {
        // Collect all dates from parse result
        var allDates: [Date] = []
        allDates.append(contentsOf: result.flights.compactMap(\.departureTime))
        allDates.append(contentsOf: result.flights.compactMap(\.arrivalTime))
        allDates.append(contentsOf: result.hotels.compactMap(\.checkIn))
        allDates.append(contentsOf: result.hotels.compactMap(\.checkOut))
        allDates.append(contentsOf: result.carRentals.compactMap(\.pickupTime))
        allDates.sort()
        
        let startDate = allDates.first ?? .now
        let endDate = allDates.last ?? startDate
        
        // Try to find an existing trip within the same date range
        let descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate<Trip> { trip in
                trip.statusRaw != "completed"
            }
        )
        
        if let existingTrips = try? modelContext.fetch(descriptor) {
            for trip in existingTrips {
                // Check if dates overlap
                let overlapStart = max(trip.startDate, startDate)
                let overlapEnd = min(trip.endDate, endDate)
                if overlapStart <= overlapEnd {
                    // Extend trip dates if needed
                    if startDate < trip.startDate { trip.startDate = startDate }
                    if endDate > trip.endDate { trip.endDate = endDate }
                    return trip
                }
                
                // Within 3 days of existing trip
                let daysBefore = Calendar.current.dateComponents([.day], from: startDate, to: trip.startDate).day ?? 999
                let daysAfter = Calendar.current.dateComponents([.day], from: trip.endDate, to: endDate).day ?? 999
                if abs(daysBefore) <= 3 || abs(daysAfter) <= 3 {
                    if startDate < trip.startDate { trip.startDate = startDate }
                    if endDate > trip.endDate { trip.endDate = endDate }
                    return trip
                }
            }
        }
        
        // Create new trip
        let trip = Trip(
            name: result.suggestedTripName.isEmpty ? "New Trip" : result.suggestedTripName,
            destination: result.suggestedDestination,
            startDate: startDate,
            endDate: endDate,
            statusRaw: "planning"
        )
        modelContext.insert(trip)
        return trip
    }
}
