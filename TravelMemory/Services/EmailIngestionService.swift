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

        // Booking.com FLIGHT links contain no itinerary data at all —
        // explain the working path instead of importing garbage
        if BookingShareImporter.isFlightLink(body) {
            var result = EmailParser.ParseResult()
            result.overallConfidence = 0.1
            result.issues.append("Booking.com flight links don't contain your flight details. Instead: open the confirmation email and use Paste Booking Confirmation, or Import from Calendar if the flight is in your calendar.")
            return result
        }

        // A hotel shared from the Booking.com app arrives as a link —
        // import it as a hotel, not a guessy email parse
        if BookingShareImporter.isBookingLink(body), sender.isEmpty {
            if let hotel = await BookingShareImporter.hotelImport(from: body) {
                var result = EmailParser.ParseResult()
                result.hotels.append(hotel)
                result.overallConfidence = hotel.confidence
                result.suggestedDestination = hotel.hotelName
                result.suggestedTripName = "Trip"
                result.issues.append("Imported from a Booking.com link — set the check-in dates after accepting.")
                return result
            }
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
        var skippedDuplicates = 0

        // Extend the trip's dates if the imported items fall outside them
        if targetTrip != nil {
            let dates = parsedDates(in: result)
            if let earliest = dates.first, earliest < trip.startDate { trip.startDate = earliest }
            if let latest = dates.last, latest > trip.endDate { trip.endDate = latest }
        }

        for flightData in result.flights {
            if Self.isDuplicate(flight: flightData, in: trip, calendar: trip.calendar) { skippedDuplicates += 1; continue }
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
            flight.timeZoneID = flightData.departureTimeZoneID
            flight.arrivalTimeZoneID = flightData.arrivalTimeZoneID
            flight.cost = flightData.cost
            flight.currencyCode = flightData.currencyCode
            trip.flights.append(flight)
            modelContext.insert(flight)
        }

        for hotelData in result.hotels {
            if Self.isDuplicate(hotel: hotelData, in: trip, calendar: trip.calendar) { skippedDuplicates += 1; continue }
            let hotel = HotelBooking(
                hotelName: hotelData.hotelName,
                address: hotelData.address,
                checkInDate: hotelData.checkIn ?? trip.startDate,
                checkOutDate: hotelData.checkOut ?? hotelData.checkIn ?? trip.endDate,
                confirmationCode: hotelData.confirmationCode,
                confidence: hotelData.confidence
            )
            hotel.timeZoneID = hotelData.timeZoneID
            hotel.cost = hotelData.cost
            hotel.currencyCode = hotelData.currencyCode
            trip.hotels.append(hotel)
            modelContext.insert(hotel)
        }

        for carData in result.carRentals {
            if Self.isDuplicate(car: carData, in: trip, calendar: trip.calendar) { skippedDuplicates += 1; continue }
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
            car.timeZoneID = carData.timeZoneID
            car.cost = carData.cost
            car.currencyCode = carData.currencyCode
            trip.carRentals.append(car)
            modelContext.insert(car)
        }

        for diningData in result.dining {
            if Self.isDuplicate(dining: diningData, in: trip, calendar: trip.calendar) { skippedDuplicates += 1; continue }
            let dining = DiningReservation(
                restaurantName: diningData.restaurantName,
                address: diningData.address,
                reservationTime: diningData.reservationTime ?? trip.startDate,
                partySize: diningData.partySize,
                notes: diningData.notes,
                confidence: diningData.confidence
            )
            dining.timeZoneID = diningData.timeZoneID
            dining.cost = diningData.cost
            dining.currencyCode = diningData.currencyCode
            trip.dining.append(dining)
            modelContext.insert(dining)
        }

        for activityData in result.activities {
            if Self.isDuplicate(activity: activityData, in: trip, calendar: trip.calendar) { skippedDuplicates += 1; continue }
            let activity = TripActivity(
                activityName: activityData.activityName,
                location: activityData.location,
                startTime: activityData.startTime ?? trip.startDate,
                endTime: activityData.endTime ?? activityData.startTime ?? trip.startDate,
                notes: activityData.notes,
                confidence: activityData.confidence
            )
            activity.timeZoneID = activityData.timeZoneID
            activity.cost = activityData.cost
            activity.currencyCode = activityData.currencyCode
            trip.activities.append(activity)
            modelContext.insert(activity)
        }

        // Record the source email. Low-confidence parses stay in the
        // Inbox review queue for a second look even after acceptance.
        var issues = result.issues
        if skippedDuplicates > 0 {
            issues.append("Skipped \(skippedDuplicates) item\(skippedDuplicates == 1 ? "" : "s") already in this trip")
        }
        let parsedEmail = ParsedEmail(
            subject: subject,
            senderEmail: sender,
            rawBody: body,
            receivedAt: .now,
            statusRaw: result.overallConfidence >= 0.7 ? "accepted" : "needsReview",
            overallConfidence: result.overallConfidence,
            issues: issues
        )
        trip.parsedEmails.append(parsedEmail)
        modelContext.insert(parsedEmail)

        modelContext.saveOrLog()

        TripNotifications.resync(trip: trip)
        CalendarSyncService.requestResync(context: modelContext)

        return trip
    }

    // MARK: - Duplicate Detection

    /// Human-readable descriptions of parsed items that already exist in
    /// the trip — shown on the review screen before accepting.
    static func duplicateDescriptions(in result: EmailParser.ParseResult, against trip: Trip) -> [String] {
        var found: [String] = []
        let cal = trip.calendar

        for flight in result.flights where isDuplicate(flight: flight, in: trip, calendar: cal) {
            found.append("Flight \(flight.flightNumber.isEmpty ? flight.confirmationCode : flight.flightNumber)")
        }
        for hotel in result.hotels where isDuplicate(hotel: hotel, in: trip, calendar: cal) {
            found.append(hotel.hotelName.isEmpty ? "a hotel booking" : hotel.hotelName)
        }
        for car in result.carRentals where isDuplicate(car: car, in: trip, calendar: cal) {
            found.append(car.company.isEmpty ? "a car rental" : car.company)
        }
        for dining in result.dining where isDuplicate(dining: dining, in: trip, calendar: cal) {
            found.append(dining.restaurantName.isEmpty ? "a reservation" : dining.restaurantName)
        }
        for activity in result.activities where isDuplicate(activity: activity, in: trip, calendar: cal) {
            found.append(activity.activityName.isEmpty ? "an activity" : activity.activityName)
        }
        return found
    }

    private static func isDuplicate(flight data: EmailParser.FlightParseData, in trip: Trip, calendar: Calendar) -> Bool {
        trip.flights.contains { existing in
            if !data.flightNumber.isEmpty,
               existing.flightNumber.caseInsensitiveCompare(data.flightNumber) == .orderedSame,
               let departure = data.departureTime,
               calendar.isDate(existing.departureTime, inSameDayAs: departure) {
                return true
            }
            if data.flightNumber.isEmpty, !data.confirmationCode.isEmpty,
               existing.confirmationCode.caseInsensitiveCompare(data.confirmationCode) == .orderedSame {
                return true
            }
            return false
        }
    }

    private static func isDuplicate(hotel data: EmailParser.HotelParseData, in trip: Trip, calendar: Calendar) -> Bool {
        trip.hotels.contains { existing in
            guard !data.hotelName.isEmpty,
                  existing.hotelName.caseInsensitiveCompare(data.hotelName) == .orderedSame else { return false }
            guard let checkIn = data.checkIn else { return true }
            return calendar.isDate(existing.checkInDate, inSameDayAs: checkIn)
        }
    }

    private static func isDuplicate(car data: EmailParser.CarRentalParseData, in trip: Trip, calendar: Calendar) -> Bool {
        trip.carRentals.contains { existing in
            guard !data.company.isEmpty,
                  existing.company.caseInsensitiveCompare(data.company) == .orderedSame else { return false }
            guard let pickup = data.pickupTime else { return true }
            return calendar.isDate(existing.pickupTime, inSameDayAs: pickup)
        }
    }

    private static func isDuplicate(dining data: EmailParser.DiningParseData, in trip: Trip, calendar: Calendar) -> Bool {
        trip.dining.contains { existing in
            guard !data.restaurantName.isEmpty,
                  existing.restaurantName.caseInsensitiveCompare(data.restaurantName) == .orderedSame else { return false }
            guard let time = data.reservationTime else { return false }
            return calendar.isDate(existing.reservationTime, inSameDayAs: time)
        }
    }

    private static func isDuplicate(activity data: EmailParser.ActivityParseData, in trip: Trip, calendar: Calendar) -> Bool {
        trip.activities.contains { existing in
            guard !data.activityName.isEmpty,
                  existing.activityName.caseInsensitiveCompare(data.activityName) == .orderedSame else { return false }
            guard let start = data.startTime else { return false }
            return calendar.isDate(existing.startTime, inSameDayAs: start)
        }
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
            // Plain fetch + in-memory filter: the #Predicate string
            // comparison traps inside SwiftData on some configurations,
            // and trip counts are tiny anyway.
            let descriptor = FetchDescriptor<Trip>()

            if let allTrips = try? modelContext.fetch(descriptor) {
                let existingTrips = allTrips.filter { $0.statusRaw != TripStatus.completed.rawValue }
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
