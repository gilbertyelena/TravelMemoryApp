//
//  EmailIngestionService.swift
//  TravelMemory
//
//  Service layer for the email-import workflow.
//
//  The flow is two-phase: `parse` extracts structured data without
//  touching the store, the UI shows the result for review, and only
//  an explicit accept calls `commit` to persist the trip and items.
//

import Foundation
import SwiftData

@MainActor
final class EmailIngestionService: ObservableObject {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Parse raw email or calendar content. Writes nothing — safe to call
    /// speculatively. Calendar (.ics) payloads are detected by content, so
    /// every entry point (paste, share, file import) handles them.
    nonisolated static func parse(subject: String, body: String, sender: String) -> EmailParser.ParseResult {
        if ICSParser.isCalendar(body) {
            return ICSParser.parse(body)
        }
        return EmailParser.parse(subject: subject, body: body, sender: sender)
    }

    /// Like `parse`, but also understands shared Google Maps links —
    /// a restaurant link shared from Google Maps becomes a dining item
    /// instead of a meaningless email parse.
    nonisolated static func parseContent(subject: String, body: String, sender: String) async -> EmailParser.ParseResult {
        if GoogleMapsLinkParser.isMapsLink(body) {
            var result = EmailParser.ParseResult()
            if let place = await GoogleMapsLinkParser.expandAndParse(body) {
                var dining = EmailParser.DiningParseData(
                    restaurantName: place.name,
                    confidence: 0.85
                )
                dining.reservationTime = nil
                result.dining.append(dining)
                result.overallConfidence = 0.85
                result.suggestedTripName = "New Trip"
                result.issues.append("Imported from a Google Maps link — set the date and trip after accepting, or paste the link inside the right trip's dining editor instead.")
            } else {
                result.issues.append("Couldn't read a place from that Google Maps link")
                result.overallConfidence = 0.1
            }
            return result
        }
        return parse(subject: subject, body: body, sender: sender)
    }

    /// Persist a reviewed parse result: find or create the matching trip
    /// (or use `targetTrip` when importing from a specific trip's screen),
    /// insert the itinerary items, and record the source email.
    /// Call only after the user has accepted the result.
    @discardableResult
    func commit(
        _ result: EmailParser.ParseResult,
        subject: String,
        body: String,
        sender: String,
        into targetTrip: Trip? = nil
    ) -> Trip {
        let trip = targetTrip ?? findOrCreateTrip(for: result)

        // Extend the trip's dates if the imported items fall outside them
        if targetTrip != nil {
            let dates = parsedDates(in: result)
            if let earliest = dates.first, earliest < trip.startDate { trip.startDate = earliest }
            if let latest = dates.last, latest > trip.endDate { trip.endDate = latest }
        }

        for flightData in result.flights {
            let flight = FlightSegment(
                airline: flightData.airline,
                flightNumber: flightData.flightNumber,
                departureAirport: flightData.departureAirport,
                departureCity: flightData.departureCity,
                arrivalAirport: flightData.arrivalAirport,
                arrivalCity: flightData.arrivalCity,
                // A missing date is already flagged as an issue by the parser;
                // anchor the item to the trip rather than to "now".
                departureTime: flightData.departureTime ?? trip.startDate,
                arrivalTime: flightData.arrivalTime ?? flightData.departureTime ?? trip.startDate,
                gate: flightData.gate,
                seat: flightData.seat,
                confirmationCode: flightData.confirmationCode,
                confidence: flightData.confidence
            )
            flight.cost = flightData.cost
            flight.currencyCode = flightData.currencyCode
            trip.flights.append(flight)
            modelContext.insert(flight)
        }

        for hotelData in result.hotels {
            let hotel = HotelBooking(
                hotelName: hotelData.hotelName,
                address: hotelData.address,
                checkInDate: hotelData.checkIn ?? trip.startDate,
                checkOutDate: hotelData.checkOut ?? hotelData.checkIn ?? trip.endDate,
                confirmationCode: hotelData.confirmationCode,
                confidence: hotelData.confidence
            )
            hotel.cost = hotelData.cost
            hotel.currencyCode = hotelData.currencyCode
            trip.hotels.append(hotel)
            modelContext.insert(hotel)
        }

        for carData in result.carRentals {
            let car = CarRentalBooking(
                company: carData.company,
                vehicleType: carData.vehicleType,
                pickupTime: carData.pickupTime ?? trip.startDate,
                dropoffTime: carData.dropoffTime ?? carData.pickupTime ?? trip.endDate,
                pickupLocation: carData.pickupLocation,
                confirmationCode: carData.confirmationCode,
                isPrepaid: carData.isPrepaid,
                confidence: carData.confidence
            )
            car.cost = carData.cost
            car.currencyCode = carData.currencyCode
            trip.carRentals.append(car)
            modelContext.insert(car)
        }

        for diningData in result.dining {
            let dining = DiningReservation(
                restaurantName: diningData.restaurantName,
                address: diningData.address,
                reservationTime: diningData.reservationTime ?? trip.startDate,
                partySize: diningData.partySize,
                notes: diningData.notes,
                confidence: diningData.confidence
            )
            dining.cost = diningData.cost
            dining.currencyCode = diningData.currencyCode
            trip.dining.append(dining)
            modelContext.insert(dining)
        }

        for activityData in result.activities {
            let activity = TripActivity(
                activityName: activityData.activityName,
                location: activityData.location,
                startTime: activityData.startTime ?? trip.startDate,
                endTime: activityData.endTime ?? activityData.startTime ?? trip.startDate,
                notes: activityData.notes,
                confidence: activityData.confidence
            )
            activity.cost = activityData.cost
            activity.currencyCode = activityData.currencyCode
            trip.activities.append(activity)
            modelContext.insert(activity)
        }

        // Record the source email. Low-confidence parses stay in the
        // Inbox review queue for a second look even after acceptance.
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

        modelContext.saveOrLog()

        TripNotifications.resync(trip: trip)

        return trip
    }

    /// All dates extracted by a parse, sorted ascending.
    private func parsedDates(in result: EmailParser.ParseResult) -> [Date] {
        var allDates: [Date] = []
        allDates.append(contentsOf: result.flights.compactMap(\.departureTime))
        allDates.append(contentsOf: result.flights.compactMap(\.arrivalTime))
        allDates.append(contentsOf: result.hotels.compactMap(\.checkIn))
        allDates.append(contentsOf: result.hotels.compactMap(\.checkOut))
        allDates.append(contentsOf: result.carRentals.compactMap(\.pickupTime))
        allDates.append(contentsOf: result.dining.compactMap(\.reservationTime))
        allDates.append(contentsOf: result.activities.compactMap(\.startTime))
        return allDates.sorted()
    }

    /// Find a trip whose dates match the parse result, or create a new one.
    private func findOrCreateTrip(for result: EmailParser.ParseResult) -> Trip {
        let allDates = parsedDates(in: result)

        // Only match against existing trips when we actually parsed dates.
        // Otherwise a dateless email would "overlap" whatever trip is
        // happening right now and merge into it.
        if let startDate = allDates.first, let endDate = allDates.last {
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
        }

        let trip = Trip(
            name: result.suggestedTripName.isEmpty ? "New Trip" : result.suggestedTripName,
            destination: result.suggestedDestination,
            startDate: allDates.first ?? .now,
            endDate: allDates.last ?? .now,
            statusRaw: "planning"
        )
        modelContext.insert(trip)
        return trip
    }
}
