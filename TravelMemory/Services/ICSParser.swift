//
//  ICSParser.swift
//  TravelMemory
//
//  Parses iCalendar (.ics) files — the "Add to calendar" attachments
//  from airlines, Booking.com, OpenTable and friends. Unlike email text,
//  ICS is structured: dates and times come out exact, so imports get
//  high confidence and rarely need review edits.
//

import Foundation

struct ICSParser {

    struct Event {
        var summary = ""
        var location = ""
        var details = ""
        var start: Date?
        var end: Date?
        var isAllDay = false
        var startTimeZoneID = ""
        var endTimeZoneID = ""
    }

    /// Quick check whether raw text is an iCalendar payload.
    static func isCalendar(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("BEGIN:VCALENDAR") || trimmed.contains("BEGIN:VEVENT")
    }

    // MARK: - Main Entry Point

    /// Converts a calendar file into the same result type the email
    /// parser produces, so the review/commit pipeline is shared.
    static func parse(_ text: String) -> EmailParser.ParseResult {
        let events = parseEvents(from: text)

        guard !events.isEmpty else {
            var result = EmailParser.ParseResult()
            result.issues.append("No events found in the calendar file")
            result.overallConfidence = 0.1
            return result
        }

        return parseResult(from: events)
    }

    /// Converts calendar events into the shared review/commit format.
    /// Also used by the EventKit importer (events from the Calendar app).
    static func parseResult(from events: [Event]) -> EmailParser.ParseResult {
        var result = EmailParser.ParseResult()

        for event in events {
            classify(event, into: &result)
        }

        // Structured input — confidence reflects only classification doubt
        var confidences: [Double] = []
        confidences.append(contentsOf: result.flights.map(\.confidence))
        confidences.append(contentsOf: result.hotels.map(\.confidence))
        confidences.append(contentsOf: result.carRentals.map(\.confidence))
        confidences.append(contentsOf: result.dining.map(\.confidence))
        confidences.append(contentsOf: result.activities.map(\.confidence))
        result.overallConfidence = confidences.isEmpty
            ? 0.1
            : confidences.reduce(0, +) / Double(confidences.count)

        if let firstFlight = result.flights.first {
            result.suggestedDestination = firstFlight.arrivalCity.isEmpty
                ? firstFlight.arrivalAirport
                : firstFlight.arrivalCity
            result.suggestedTripName = result.suggestedDestination.isEmpty
                ? "New Trip"
                : "\(result.suggestedDestination) Trip"
        } else if let firstHotel = result.hotels.first {
            result.suggestedDestination = firstHotel.hotelName
            result.suggestedTripName = "Trip"
        }

        return result
    }

    // MARK: - Event Classification

    private static func classify(_ event: Event, into result: inout EmailParser.ParseResult) {
        let haystack = "\(event.summary)\n\(event.location)\n\(event.details)"
        let lowered = event.summary.lowercased()

        let hasFlightNumber = !EmailParser.parseFlights(from: haystack)
            .filter { !$0.flightNumber.isEmpty }.isEmpty
        if lowered.contains("flight") || event.summary.contains("✈") || hasFlightNumber {
            // Let the text heuristics pull airports/codes out of the
            // summary, but the event's own timestamps are authoritative.
            var flight = EmailParser.parseFlights(from: haystack).first
                ?? EmailParser.FlightParseData(
                    airline: "", flightNumber: "",
                    departureAirport: "", departureCity: "",
                    arrivalAirport: "", arrivalCity: "",
                    departureTime: nil, arrivalTime: nil,
                    gate: "", seat: "", confirmationCode: "", confidence: 0.5
                )
            flight.departureTime = event.start ?? flight.departureTime
            flight.arrivalTime = event.end ?? flight.arrivalTime
            flight.departureTimeZoneID = event.startTimeZoneID
            flight.arrivalTimeZoneID = event.endTimeZoneID
            flight.confidence = 0.9
            result.flights.append(flight)
            return
        }

        let hotelKeywords = ["hotel", "check-in", "check in", "apartment", "hostel",
                             "resort", "accommodation", "stay at", "b&b", "guesthouse", "inn "]
        if hotelKeywords.contains(where: { lowered.contains($0) }) {
            var hotel = EmailParser.HotelParseData(
                hotelName: cleanedTitle(event.summary),
                address: event.location,
                checkIn: event.start,
                checkOut: event.end,
                confirmationCode: EmailParser.extractConfirmationCode(from: haystack) ?? "",
                confidence: 0.85
            )
            hotel.timeZoneID = event.startTimeZoneID
            result.hotels.append(hotel)
            return
        }

        let carKeywords = ["car rental", "rental car", "car hire", "pick up car",
                           "hertz", "avis", "sixt", "europcar", "enterprise rent", "budget rent"]
        if carKeywords.contains(where: { lowered.contains($0) }) {
            var car = EmailParser.CarRentalParseData(
                company: cleanedTitle(event.summary),
                vehicleType: "",
                pickupTime: event.start,
                dropoffTime: event.end,
                pickupLocation: event.location,
                confirmationCode: EmailParser.extractConfirmationCode(from: haystack) ?? "",
                isPrepaid: false,
                confidence: 0.85
            )
            car.timeZoneID = event.startTimeZoneID
            result.carRentals.append(car)
            return
        }

        let diningKeywords = ["dinner", "lunch", "brunch", "breakfast at", "restaurant",
                              "reservation at", "table for", "table at", "dining"]
        if diningKeywords.contains(where: { lowered.contains($0) }) {
            var dining = EmailParser.DiningParseData(
                restaurantName: cleanedTitle(event.summary),
                address: event.location,
                reservationTime: event.start,
                notes: event.details,
                confidence: 0.85
            )
            dining.timeZoneID = event.startTimeZoneID
            if let sizeMatch = haystack.range(
                of: #"(?:table|party)\s+(?:for|of)\s+(\d{1,2})"#,
                options: [.regularExpression, .caseInsensitive]
            ), let size = Int(haystack[sizeMatch].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
                dining.partySize = size
            }
            result.dining.append(dining)
            return
        }

        // Everything else becomes an activity — still a useful import
        var activity = EmailParser.ActivityParseData(
            activityName: cleanedTitle(event.summary),
            location: event.location,
            startTime: event.start,
            endTime: event.end,
            notes: event.details,
            confidence: 0.75
        )
        activity.timeZoneID = event.startTimeZoneID
        result.activities.append(activity)
    }

    /// Strips label prefixes calendar exporters like to add
    /// ("Flight: ...", "Stay at ...", "Reservation at ...").
    private static func cleanedTitle(_ summary: String) -> String {
        var title = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["flight:", "flight to", "hotel:", "stay at", "check-in:",
                        "reservation at", "reservation:", "dinner at", "lunch at", "booking:"]
        for prefix in prefixes {
            if title.lowercased().hasPrefix(prefix) {
                title = String(title.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return title.isEmpty ? summary : title
    }

    // MARK: - VEVENT Extraction

    static func parseEvents(from text: String) -> [Event] {
        var events: [Event] = []
        var current: Event?

        for line in unfoldedLines(of: text) {
            if line == "BEGIN:VEVENT" {
                current = Event()
                continue
            }
            if line == "END:VEVENT" {
                if let event = current { events.append(event) }
                current = nil
                continue
            }
            guard current != nil, let property = parseProperty(line) else { continue }

            switch property.name {
            case "SUMMARY":
                current?.summary = unescape(property.value)
            case "LOCATION":
                current?.location = unescape(property.value)
            case "DESCRIPTION":
                current?.details = unescape(property.value)
            case "DTSTART":
                let parsed = parseDate(property.value, parameters: property.parameters)
                current?.start = parsed.date
                current?.isAllDay = parsed.isAllDay
                current?.startTimeZoneID = property.parameters["TZID"] ?? (property.value.hasSuffix("Z") ? "UTC" : "")
            case "DTEND":
                current?.end = parseDate(property.value, parameters: property.parameters).date
                current?.endTimeZoneID = property.parameters["TZID"] ?? (property.value.hasSuffix("Z") ? "UTC" : "")
            default:
                break
            }
        }

        return events
    }

    /// RFC 5545 line unfolding: a line starting with a space or tab is
    /// a continuation of the previous line.
    private static func unfoldedLines(of text: String) -> [String] {
        let rawLines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var lines: [String] = []
        for raw in rawLines {
            if raw.hasPrefix(" ") || raw.hasPrefix("\t"), !lines.isEmpty {
                lines[lines.count - 1] += String(raw.dropFirst())
            } else {
                lines.append(raw)
            }
        }
        return lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Splits "NAME;PARAM=X;PARAM2=Y:value" into its parts.
    private static func parseProperty(_ line: String) -> (name: String, parameters: [String: String], value: String)? {
        // Find the first ':' that is not inside a quoted parameter value
        var insideQuotes = false
        var colonIndex: String.Index?
        for index in line.indices {
            let char = line[index]
            if char == "\"" { insideQuotes.toggle() }
            if char == ":" && !insideQuotes {
                colonIndex = index
                break
            }
        }
        guard let colon = colonIndex else { return nil }

        let head = String(line[..<colon])
        let value = String(line[line.index(after: colon)...])

        let headParts = head.components(separatedBy: ";")
        guard let name = headParts.first?.uppercased() else { return nil }

        var parameters: [String: String] = [:]
        for part in headParts.dropFirst() {
            let pair = part.components(separatedBy: "=")
            if pair.count == 2 {
                parameters[pair[0].uppercased()] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return (name, parameters, value)
    }

    private static func parseDate(_ value: String, parameters: [String: String]) -> (date: Date?, isAllDay: Bool) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // All-day: "VALUE=DATE" parameter or a bare yyyyMMdd value
        if parameters["VALUE"] == "DATE" || (value.count == 8 && !value.contains("T")) {
            formatter.dateFormat = "yyyyMMdd"
            formatter.timeZone = .current
            return (formatter.date(from: value), true)
        }

        if value.hasSuffix("Z") {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")
            return (formatter.date(from: value), false)
        }

        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        if let tzid = parameters["TZID"], let zone = TimeZone(identifier: tzid) {
            formatter.timeZone = zone
        } else {
            formatter.timeZone = .current
        }
        return (formatter.date(from: value), false)
    }

    /// RFC 5545 text unescaping.
    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
