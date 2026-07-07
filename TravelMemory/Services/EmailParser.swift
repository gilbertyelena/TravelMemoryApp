//
//  EmailParser.swift
//  TravelMemory
//
//  Parses confirmation emails from airlines, hotels, and car rental
//  companies to extract structured itinerary data.
//  Uses regex pattern matching against common booking email formats.
//

import Foundation

struct EmailParser {
    
    /// Result of parsing an email or calendar file
    struct ParseResult {
        var flights: [FlightParseData] = []
        var hotels: [HotelParseData] = []
        var carRentals: [CarRentalParseData] = []
        var dining: [DiningParseData] = []
        var activities: [ActivityParseData] = []
        var overallConfidence: Double = 0.0
        var issues: [String] = []
        var suggestedDestination: String = ""
        var suggestedTripName: String = ""
    }
    
    struct FlightParseData {
        var airline: String
        var flightNumber: String
        var departureAirport: String
        var departureCity: String
        var arrivalAirport: String
        var arrivalCity: String
        var departureTime: Date?
        var arrivalTime: Date?
        var gate: String
        var seat: String
        var confirmationCode: String
        var confidence: Double
        var cost: Double = 0
        var currencyCode: String = ""
        var departureTimeZoneID: String = ""
        var arrivalTimeZoneID: String = ""
    }
    
    struct HotelParseData {
        var hotelName: String
        var address: String
        var checkIn: Date?
        var checkOut: Date?
        var confirmationCode: String
        var confidence: Double
        var cost: Double = 0
        var currencyCode: String = ""
        var timeZoneID: String = ""
    }
    
    struct CarRentalParseData {
        var company: String
        var vehicleType: String
        var pickupTime: Date?
        var dropoffTime: Date?
        var pickupLocation: String
        var confirmationCode: String
        var isPrepaid: Bool
        var confidence: Double
        var cost: Double = 0
        var currencyCode: String = ""
        var timeZoneID: String = ""
    }

    struct DiningParseData {
        var restaurantName: String = ""
        var address: String = ""
        var reservationTime: Date?
        var partySize: Int = 2
        var notes: String = ""
        var confidence: Double = 0.5
        var cost: Double = 0
        var currencyCode: String = ""
        var timeZoneID: String = ""
    }

    struct ActivityParseData {
        var activityName: String = ""
        var location: String = ""
        var startTime: Date?
        var endTime: Date?
        var notes: String = ""
        var confidence: Double = 0.5
        var cost: Double = 0
        var currencyCode: String = ""
        var timeZoneID: String = ""
    }
    
    // MARK: - Main Parse Entry Point
    
    static func parse(subject: String, body: String, sender: String) -> ParseResult {
        var result = ParseResult()
        
        let normalizedBody = normalizeText(body)
        let normalizedSubject = normalizeText(subject)
        let combinedText = normalizedSubject + "\n" + normalizedBody
        
        // Detect what type of confirmation this is
        let isFlightEmail = detectFlightEmail(subject: normalizedSubject, body: normalizedBody, sender: sender)
        let isHotelEmail = detectHotelEmail(subject: normalizedSubject, body: normalizedBody, sender: sender)
        let isCarEmail = detectCarRentalEmail(subject: normalizedSubject, body: normalizedBody, sender: sender)
        
        if isFlightEmail {
            result.flights = parseFlights(from: combinedText)
        }
        
        if isHotelEmail {
            let hotel = parseHotelDetails(from: combinedText)
            result.hotels.append(hotel)
        }
        
        if isCarEmail {
            let car = parseCarRentalDetails(from: combinedText)
            result.carRentals.append(car)
        }
        
        // If nothing was detected, try a generic parse
        if !isFlightEmail && !isHotelEmail && !isCarEmail {
            let genericResult = genericParse(subject: normalizedSubject, body: normalizedBody)
            result = genericResult
            if result.flights.isEmpty && result.hotels.isEmpty && result.carRentals.isEmpty {
                result.issues.append("Could not identify booking type from email content")
                result.overallConfidence = 0.1
                return result
            }
        }
        
        // Calculate overall confidence
        var confidences: [Double] = []
        confidences.append(contentsOf: result.flights.map(\.confidence))
        confidences.append(contentsOf: result.hotels.map(\.confidence))
        confidences.append(contentsOf: result.carRentals.map(\.confidence))
        
        if confidences.isEmpty {
            result.overallConfidence = 0.0
        } else {
            result.overallConfidence = confidences.reduce(0, +) / Double(confidences.count)
        }
        
        // Flag issues
        for flight in result.flights {
            if flight.departureTime == nil {
                result.issues.append("Could not parse departure time for \(flight.airline) \(flight.flightNumber)")
            }
            if flight.confirmationCode.isEmpty {
                result.issues.append("No confirmation code found for flight")
            }
        }
        for hotel in result.hotels {
            if hotel.checkIn == nil {
                result.issues.append("Could not parse check-in date for \(hotel.hotelName)")
            }
        }
        
        // Suggest trip name / destination
        if let firstFlight = result.flights.first {
            result.suggestedDestination = firstFlight.arrivalCity.isEmpty ? firstFlight.arrivalAirport : firstFlight.arrivalCity
            result.suggestedTripName = result.suggestedDestination.isEmpty ? "New Trip" : "\(result.suggestedDestination) Trip"
        } else if let firstHotel = result.hotels.first {
            result.suggestedDestination = firstHotel.hotelName
            result.suggestedTripName = "Trip"
        }
        
        return result
    }
    
    // MARK: - Detection
    
    private static func detectFlightEmail(subject: String, body: String, sender: String) -> Bool {
        // NB: no generic terms like "booking confirmation" here — hotel
        // confirmations use them too and would be misrouted to flights
        let flightKeywords = [
            "flight confirmation", "e-ticket",
            "itinerary receipt", "boarding pass", "flight reservation",
            "flight details", "air reservation",
            "ticket confirmation", "flight booking"
        ]
        let airlineSenders = [
            "united.com", "delta.com", "aa.com", "southwest.com",
            "lufthansa.com", "britishairways.com", "airfrance.com",
            "klm.com", "emirates.com", "qantas.com", "virginatlantic.com",
            "jetblue.com", "spirit.com", "alaskaair.com", "ryanair.com",
            "easyjet.com", "booking.com", "expedia.com", "kayak.com",
            "google.com", "tripit.com"
        ]
        
        let subjectMatch = flightKeywords.contains { subject.lowercased().contains($0) }
        let senderMatch = airlineSenders.contains { sender.lowercased().contains($0) }
        let bodyMatch = body.lowercased().contains("flight") && 
                        (body.lowercased().contains("depart") || body.lowercased().contains("arrive"))
        
        return subjectMatch || senderMatch || bodyMatch
    }
    
    private static func detectHotelEmail(subject: String, body: String, sender: String) -> Bool {
        let hotelKeywords = [
            "hotel confirmation", "reservation confirmed", "check-in",
            "your stay", "room reservation", "hotel booking",
            "accommodation", "lodging confirmation"
        ]
        let hotelSenders = [
            "marriott.com", "hilton.com", "hyatt.com", "ihg.com",
            "accor.com", "booking.com", "hotels.com", "expedia.com",
            "airbnb.com", "vrbo.com", "kempinski.com", "fourseasons.com",
            "ritzcarlton.com"
        ]
        
        let subjectMatch = hotelKeywords.contains { subject.lowercased().contains($0) }
        let senderMatch = hotelSenders.contains { sender.lowercased().contains($0) }
        let lowered = body.lowercased()
        let bodyMatch = (lowered.contains("check-in") || lowered.contains("check in"))
            && (lowered.contains("check-out") || lowered.contains("check out"))

        return subjectMatch || senderMatch || bodyMatch
    }
    
    private static func detectCarRentalEmail(subject: String, body: String, sender: String) -> Bool {
        let carKeywords = [
            "car rental", "rental confirmation", "vehicle reservation",
            "pickup", "rent a car", "car reservation"
        ]
        let carSenders = [
            "hertz.com", "avis.com", "enterprise.com", "nationalcar.com",
            "budget.com", "sixt.com", "europcar.com", "alamo.com"
        ]
        
        let subjectMatch = carKeywords.contains { subject.lowercased().contains($0) }
        let senderMatch = carSenders.contains { sender.lowercased().contains($0) }
        
        return subjectMatch || senderMatch
    }
    
    // MARK: - Flight Parsing

    /// Airline display names keyed by IATA designator.
    static let airlinesByCode: [String: String] = [
        "LH": "Lufthansa", "UA": "United", "DL": "Delta",
        "AA": "American Airlines", "WN": "Southwest",
        "BA": "British Airways", "AF": "Air France",
        "KL": "KLM", "EK": "Emirates", "VS": "Virgin Atlantic",
        "B6": "JetBlue", "AS": "Alaska Airlines", "QF": "Qantas",
        "FR": "Ryanair", "U2": "EasyJet", "NK": "Spirit",
        "W6": "Wizz Air", "TK": "Turkish Airlines", "LX": "Swiss",
        "OS": "Austrian", "IB": "Iberia", "VY": "Vueling",
        "TP": "TAP Air Portugal", "EI": "Aer Lingus", "DY": "Norwegian",
        "EW": "Eurowings", "AY": "Finnair", "LO": "LOT Polish Airlines",
        "SK": "SAS", "AC": "Air Canada", "EY": "Etihad",
        "QR": "Qatar Airways", "SQ": "Singapore Airlines",
        "CX": "Cathay Pacific", "NH": "ANA", "JL": "Japan Airlines",
        "FI": "Icelandair"
    ]

    /// Parses every flight segment in the text. Booking confirmations
    /// commonly contain several legs (outbound + return, connections);
    /// the text is split at each distinct flight number and each chunk
    /// parsed separately, then chunks describing the same flight are merged.
    static func parseFlights(from text: String) -> [FlightParseData] {
        // Occurrences of flight numbers with a known airline designator
        let candidates = allMatchRanges(in: text, pattern: #"\b([A-Z]{2})\s?(\d{1,4})\b"#)
            .filter { airlinesByCode.keys.contains(String($0.value.prefix(2))) }

        let uniqueNumbers = Set(candidates.map { $0.value.replacingOccurrences(of: " ", with: "") })
        guard uniqueNumbers.count >= 2 else {
            return [parseFlightDetails(from: text)]
        }

        // Split the text into chunks at each occurrence (the first chunk
        // keeps the preamble so subject-line context isn't lost).
        let nsText = text as NSString
        var segments: [FlightParseData] = []
        for (index, candidate) in candidates.enumerated() {
            let start = index == 0 ? 0 : candidate.range.location
            let end = index + 1 < candidates.count ? candidates[index + 1].range.location : nsText.length
            guard end > start else { continue }
            let chunk = nsText.substring(with: NSRange(location: start, length: end - start))

            var flight = parseFlightDetails(from: chunk)
            // The chunk starts at this candidate — it owns the segment.
            flight.flightNumber = candidate.value.replacingOccurrences(of: " ", with: "")
            if flight.airline.isEmpty {
                flight.airline = airlinesByCode[String(flight.flightNumber.prefix(2))] ?? ""
            }
            segments.append(flight)
        }

        // Merge chunks that describe the same flight (e.g. the subject
        // line repeats the outbound number without any details).
        var merged: [FlightParseData] = []
        for segment in segments {
            if let existingIndex = merged.firstIndex(where: { $0.flightNumber == segment.flightNumber }) {
                merged[existingIndex] = mergeFlights(merged[existingIndex], segment)
            } else {
                merged.append(segment)
            }
        }
        return merged
    }

    /// Field-wise merge of two parses of the same flight, preferring
    /// whichever side actually extracted a value.
    private static func mergeFlights(_ a: FlightParseData, _ b: FlightParseData) -> FlightParseData {
        var result = a
        if result.airline.isEmpty { result.airline = b.airline }
        if result.departureAirport.isEmpty { result.departureAirport = b.departureAirport }
        if result.departureCity.isEmpty { result.departureCity = b.departureCity }
        if result.arrivalAirport.isEmpty { result.arrivalAirport = b.arrivalAirport }
        if result.arrivalCity.isEmpty { result.arrivalCity = b.arrivalCity }
        if result.departureTime == nil { result.departureTime = b.departureTime }
        if result.arrivalTime == nil { result.arrivalTime = b.arrivalTime }
        if result.gate.isEmpty { result.gate = b.gate }
        if result.seat.isEmpty { result.seat = b.seat }
        if result.confirmationCode.isEmpty { result.confirmationCode = b.confirmationCode }
        result.confidence = max(result.confidence, b.confidence)
        return result
    }

    /// URLs are stripped before pattern scanning — their query blobs are
    /// full of uppercase letter/digit runs that fake airport codes and
    /// flight numbers (the Booking.com share-link bug).
    private static func strippingURLs(_ text: String) -> String {
        text.replacingOccurrences(of: #"https?://\S+"#, with: " ", options: .regularExpression)
    }

    private static func parseFlightDetails(from rawText: String) -> FlightParseData {
        let text = strippingURLs(rawText)
        var flight = FlightParseData(
            airline: "", flightNumber: "",
            departureAirport: "", departureCity: "",
            arrivalAirport: "", arrivalCity: "",
            departureTime: nil, arrivalTime: nil,
            gate: "", seat: "",
            confirmationCode: "", confidence: 0.5
        )
        
        var confidenceBoost = 0.0

        // Extract airline name. Whole-word match, longest names first —
        // plain substring search finds "ANA" inside "Ryanair".
        var airlineCode: String?
        for (code, name) in airlinesByCode.sorted(by: { $0.value.count > $1.value.count }) {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\b"
            if text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                flight.airline = name
                airlineCode = code
                confidenceBoost += 0.1
                break
            }
        }

        // Extract flight number (e.g. "LH411", "UA 1234", "DL 456").
        // Prefer a number carrying a known airline designator — a bare
        // [A-Z]{2}\d+ pattern matches far too much ordinary text.
        let flightNumberCandidates = allMatches(in: text, pattern: #"\b([A-Z]{2})\s?(\d{1,4})\b"#)
        for candidate in flightNumberCandidates {
            let compact = candidate.replacingOccurrences(of: " ", with: "")
            let designator = String(compact.prefix(2))
            let matchesDetectedAirline = airlineCode.map { designator == $0 } ?? false
            if matchesDetectedAirline || airlinesByCode.keys.contains(designator) {
                flight.flightNumber = compact
                confidenceBoost += 0.1
                break
            }
        }
        // Fall back to the first generic candidate only if nothing better exists
        if flight.flightNumber.isEmpty, let first = flightNumberCandidates.first {
            flight.flightNumber = first.replacingOccurrences(of: " ", with: "")
        }

        // Extract airport codes (3-letter IATA codes). Match against the
        // original text — codes appear uppercase in booking emails, and
        // uppercasing everything would turn every word into a candidate.
        let airportPattern = #"\b([A-Z]{3})\b"#
        let airports = allMatches(in: text, pattern: airportPattern)
            .filter { isLikelyAirportCode($0) }

        if airports.count >= 2 {
            flight.departureAirport = airports[0]
            // The departure code often repeats (header + details);
            // the arrival is the first *different* code.
            flight.arrivalAirport = airports.dropFirst().first { $0 != airports[0] } ?? airports[1]
            confidenceBoost += 0.15
        }
        
        // Extract dates
        let dates = extractDates(from: text)
        if let firstDate = dates.first {
            flight.departureTime = firstDate
            confidenceBoost += 0.1
        }
        if dates.count >= 2 {
            flight.arrivalTime = dates[1]
        }
        
        // Extract confirmation/booking reference
        if let confCode = extractConfirmationCode(from: text) {
            flight.confirmationCode = confCode
            confidenceBoost += 0.1
        }
        
        // Extract gate
        if let gate = firstMatch(in: text, pattern: #"[Gg]ate\s*:?\s*([A-Z]?\d{1,3}[A-Z]?)"#) {
            flight.gate = gate.replacingOccurrences(of: "gate", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
            confidenceBoost += 0.05
        }
        
        // Extract seat
        if let seat = firstMatch(in: text, pattern: #"[Ss]eat\s*:?\s*(\d{1,2}[A-Z])"#) {
            flight.seat = seat.replacingOccurrences(of: "seat", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
            confidenceBoost += 0.05
        }
        
        flight.confidence = min(1.0, 0.3 + confidenceBoost)
        return flight
    }
    
    // MARK: - Hotel Parsing
    
    private static func parseHotelDetails(from text: String) -> HotelParseData {
        var hotel = HotelParseData(
            hotelName: "", address: "",
            checkIn: nil, checkOut: nil,
            confirmationCode: "", confidence: 0.5
        )
        
        var confidenceBoost = 0.0
        
        // Extract hotel name — look for common patterns
        let hotelBrands = [
            "Marriott", "Hilton", "Hyatt", "Holiday Inn", "Sheraton",
            "Westin", "Ritz-Carlton", "Four Seasons", "InterContinental",
            "Crowne Plaza", "Kempinski", "Mandarin Oriental", "Park Hyatt",
            "W Hotel", "St. Regis", "Fairmont", "Sofitel", "Novotel",
            "Radisson", "Best Western", "Hampton Inn", "Courtyard"
        ]
        
        for brand in hotelBrands {
            if text.localizedCaseInsensitiveContains(brand) {
                // Capture the full name around the brand, staying on one
                // line and stopping at punctuation ("Hotel Vier
                // Jahreszeiten Kempinski", not just "Kempinski").
                let escaped = NSRegularExpression.escapedPattern(for: brand)
                let namePattern = "(?:[A-Za-z][A-Za-z '&\\-]{0,40})?" + escaped + "[A-Za-z0-9 '&\\-]{0,40}(?=[\\n,.]|$)"
                if let fullName = firstMatch(in: text, pattern: namePattern) {
                    hotel.hotelName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    hotel.hotelName = brand
                }
                confidenceBoost += 0.15
                break
            }
        }

        // If no brand match, look for "Hotel" keyword
        if hotel.hotelName.isEmpty {
            if let match = firstMatch(in: text, pattern: #"(?:Hotel|Inn|Resort|Lodge) [A-Za-z][A-Za-z0-9 '&\-]{1,40}(?=[\n,.]|$)"#) {
                hotel.hotelName = match.trimmingCharacters(in: .whitespacesAndNewlines)
                confidenceBoost += 0.1
            }
        }
        
        // Extract dates
        let dates = extractDates(from: text)
        if dates.count >= 2 {
            hotel.checkIn = dates[0]
            hotel.checkOut = dates[1]
            confidenceBoost += 0.2
        } else if let firstDate = dates.first {
            hotel.checkIn = firstDate
            confidenceBoost += 0.1
        }
        
        // Confirmation code
        if let code = extractConfirmationCode(from: text) {
            hotel.confirmationCode = code
            confidenceBoost += 0.1
        }
        
        hotel.confidence = min(1.0, 0.3 + confidenceBoost)
        return hotel
    }
    
    // MARK: - Car Rental Parsing
    
    private static func parseCarRentalDetails(from text: String) -> CarRentalParseData {
        var car = CarRentalParseData(
            company: "", vehicleType: "",
            pickupTime: nil, dropoffTime: nil,
            pickupLocation: "", confirmationCode: "",
            isPrepaid: false, confidence: 0.5
        )
        
        var confidenceBoost = 0.0
        
        // Rental companies
        let companies = [
            "Hertz", "Avis", "Enterprise", "National",
            "Budget", "Sixt", "Europcar", "Alamo", "Dollar", "Thrifty"
        ]
        for company in companies {
            if text.localizedCaseInsensitiveContains(company) {
                car.company = company
                confidenceBoost += 0.15
                break
            }
        }
        
        // Vehicle type
        let vehicles = [
            "Economy", "Compact", "Midsize", "Full-Size", "SUV",
            "Luxury", "Premium", "Convertible", "Minivan",
            "BMW", "Mercedes", "Audi", "Toyota", "Honda"
        ]
        for vehicle in vehicles {
            if text.localizedCaseInsensitiveContains(vehicle) {
                car.vehicleType = vehicle
                confidenceBoost += 0.1
                break
            }
        }
        
        // Dates
        let dates = extractDates(from: text)
        if dates.count >= 2 {
            car.pickupTime = dates[0]
            car.dropoffTime = dates[1]
            confidenceBoost += 0.15
        }
        
        // Pre-paid
        if text.localizedCaseInsensitiveContains("pre-paid") ||
           text.localizedCaseInsensitiveContains("prepaid") {
            car.isPrepaid = true
        }
        
        // Confirmation
        if let code = extractConfirmationCode(from: text) {
            car.confirmationCode = code
            confidenceBoost += 0.1
        }
        
        car.confidence = min(1.0, 0.3 + confidenceBoost)
        return car
    }
    
    // MARK: - Generic Parse (fallback)
    
    private static func genericParse(subject: String, body: String) -> ParseResult {
        var result = ParseResult()
        let combinedText = subject + "\n" + body
        
        // Check if it looks like it has flight info. Generic content gets
        // the STRICT tests: recognised IATA codes and known airline
        // designators only, with URLs stripped — marketing text and link
        // parameters must not conjure flights.
        let scanText = strippingURLs(combinedText)
        let hasAirportCodes = allMatches(in: scanText, pattern: #"\b([A-Z]{3})\b"#)
            .filter { knownAirportCodes.contains($0) }
            .count >= 2
        let hasFlightNumber = allMatches(in: scanText, pattern: #"\b([A-Z]{2})\s?(\d{1,4})\b"#)
            .contains { airlinesByCode.keys.contains(String($0.replacingOccurrences(of: " ", with: "").prefix(2))) }
        
        if hasAirportCodes || hasFlightNumber {
            result.flights = parseFlights(from: combinedText)
        }
        
        // Check for hotel mentions
        if combinedText.localizedCaseInsensitiveContains("hotel") ||
           combinedText.localizedCaseInsensitiveContains("check-in") ||
           combinedText.localizedCaseInsensitiveContains("check in") {
            result.hotels.append(parseHotelDetails(from: combinedText))
        }
        
        return result
    }
    
    // MARK: - Helpers
    
    private static func normalizeText(_ text: String) -> String {
        // Strip HTML tags
        var cleaned = text.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        // Collapse runs of spaces/tabs but keep line breaks — several
        // extraction patterns rely on line structure to bound matches.
        cleaned = cleaned.replacingOccurrences(
            of: "[ \\t]+",
            with: " ",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: "\\n\\s*\\n+",
            with: "\n",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        guard let matchRange = Range(match.range, in: text) else { return nil }
        return String(text[matchRange])
    }

    private static func allMatches(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap {
            guard let matchRange = Range($0.range, in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    /// All matches of a pattern along with their location in the text,
    /// so results from several patterns can be merged in document order.
    private static func allMatchRanges(in text: String, pattern: String) -> [(range: NSRange, value: String)] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap {
            guard let matchRange = Range($0.range, in: text) else { return nil }
            return ($0.range, String(text[matchRange]))
        }
    }
    
    /// Extracts dates in the order they appear in the text (booking emails
    /// list events in itinerary order), attaching times to dates by their
    /// document position. Sorting here would mis-pair overnight flights,
    /// whose arrival time-of-day is earlier than the departure.
    private static func extractDates(from text: String) -> [Date] {
        let formatters: [(String, String)] = [
            // "Oct 12, 2025"
            (#"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2},?\s+\d{4}\b"#, "MMM d, yyyy"),
            // "12 Oct 2025"
            (#"\b\d{1,2}\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{4}\b"#, "d MMM yyyy"),
            // "2025-10-12"
            (#"\b\d{4}-\d{2}-\d{2}\b"#, "yyyy-MM-dd"),
            // "10/12/2025"
            (#"\b\d{2}/\d{2}/\d{4}\b"#, "MM/dd/yyyy"),
        ]

        // Collect matches from every format, then merge by position so the
        // result reflects document order rather than pattern order.
        var found: [(range: NSRange, date: Date)] = []
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US")

        for (pattern, format) in formatters {
            fmt.dateFormat = format
            for (range, value) in allMatchRanges(in: text, pattern: pattern) {
                let cleanMatch = value.replacingOccurrences(of: ",", with: "")
                if let date = fmt.date(from: cleanMatch) {
                    found.append((range, date))
                }
            }
        }

        found.sort { $0.range.location < $1.range.location }

        // Drop overlapping matches (the same substring matched by two patterns)
        var dates: [Date] = []
        var lastEnd = -1
        for (range, date) in found {
            guard range.location >= lastEnd else { continue }
            dates.append(date)
            lastEnd = range.location + range.length
        }

        // Attach times to dates by document position. Keep the whitespace
        // before AM/PM on one line — \s would swallow the trailing newline
        // and break DateFormatter parsing.
        let timePattern = #"\b(\d{1,2}:\d{2}(?:[ \t]?(?:AM|PM|am|pm))?)\b"#
        let times = allMatchRanges(in: text, pattern: timePattern)
            .sorted { $0.range.location < $1.range.location }
            .map(\.value)

        if !dates.isEmpty && !times.isEmpty {
            let timeFmt = DateFormatter()
            timeFmt.locale = Locale(identifier: "en_US")
            let cal = Calendar.current

            for (i, time) in times.prefix(dates.count).enumerated() {
                let cleanTime = time.trimmingCharacters(in: .whitespacesAndNewlines)
                timeFmt.dateFormat = cleanTime.lowercased().contains("m") ? "h:mm a" : "HH:mm"
                if let timeDate = timeFmt.date(from: cleanTime) {
                    let hour = cal.component(.hour, from: timeDate)
                    let minute = cal.component(.minute, from: timeDate)
                    dates[i] = cal.date(bySettingHour: hour, minute: minute, second: 0, of: dates[i]) ?? dates[i]
                }
            }
        }

        return dates
    }

    /// Also used by ICSParser on event descriptions.
    static func extractConfirmationCode(from text: String) -> String? {
        // Common patterns: "Confirmation: ABC123", "Booking Ref: XYZ789", "PNR: ABCDE"
        let patterns = [
            #"(?:confirmation|booking\s*(?:ref|reference|number|code)|pnr|record\s*locator|reservation)\s*(?:#|:|\s)\s*([A-Z0-9]{5,12})"#,
            #"(?:confirmation|booking)\s*(?:#|:)\s*(\d{6,12})"#,
        ]

        // Words that follow "confirmation"/"booking" in prose and must
        // not be mistaken for codes ("BOOKING CONFIRMATION\n\nHOTEL ...")
        let stopwords: Set<String> = [
            "HOTEL", "HOTELS", "CHECK", "TOTAL", "GUEST", "GUESTS",
            "NIGHT", "NIGHTS", "ROOMS", "EMAIL", "PHONE", "DATES",
            "NUMBER", "DETAILS", "PLEASE", "THANK", "THANKS"
        ]

        var lettersOnlyCandidate: String?
        for pattern in patterns {
            // Text is uppercased so the keyword patterns need case-insensitive
            // matching; the code itself stays [A-Z0-9].
            for match in allMatches(in: text.uppercased(), pattern: pattern, options: .caseInsensitive) {
                let components = match.components(separatedBy: CharacterSet.alphanumerics.inverted)
                guard let code = components.last, code.count >= 5, !stopwords.contains(code) else { continue }
                // Codes with digits are near-certain; letters-only ones
                // (airline PNRs) are kept as a fallback
                if code.contains(where: \.isNumber) {
                    return code
                }
                if lettersOnlyCandidate == nil {
                    lettersOnlyCandidate = code
                }
            }
        }

        return lettersOnlyCandidate
    }
    
    /// Recognised IATA codes — used strictly by the generic parser and
    /// loosely (with the stopword filter) by confirmed flight emails
    static let knownAirportCodes = Set([
        "JFK", "LAX", "ORD", "SFO", "MIA", "ATL", "DFW", "DEN", "SEA", "BOS",
        "LHR", "LGW", "STN", "LTN", "CDG", "FRA", "MUC", "AMS", "FCO", "MAD",
        "BCN", "IST", "DXB", "SIN", "HKG", "NRT", "HND", "ICN", "BKK", "SYD",
        "MEL", "AKL", "EWR", "IAD", "IAH", "PHX", "MSP", "DTW", "CLT", "MCO",
        "TPA", "PHL", "ZRH", "VIE", "CPH", "OSL", "ARN", "HEL", "DUB", "EDI",
        "LIS", "GVA", "YYZ", "YVR", "MEX", "GRU", "EZE", "BOG", "SCL", "LIM",
        "PTY", "CUN", "MAN", "BHX", "BRS", "GLA", "NCE", "LYS", "MXP", "LIN",
        "NAP", "VCE", "PMI", "AGP", "ALC", "SVQ", "OPO", "ATH", "SKG", "PRG",
        "BUD", "WAW", "KRK", "OTP", "SOF", "BEG", "ZAG", "LJU", "TLV", "CAI"
    ])

    /// Checks if a 3-letter code is likely an IATA airport code
    private static func isLikelyAirportCode(_ code: String) -> Bool {
        // If it's a known code, definitely an airport
        if knownAirportCodes.contains(code) { return true }
        
        // Filter out common English 3-letter words
        let commonWords = Set([
            "THE", "AND", "FOR", "ARE", "BUT", "NOT", "YOU", "ALL", "CAN", "HAD",
            "HER", "WAS", "ONE", "OUR", "OUT", "DAY", "GET", "HAS", "HIM", "HIS",
            "HOW", "ITS", "MAY", "NEW", "NOW", "OLD", "SEE", "WAY", "WHO", "DID",
            "GOT", "LET", "SAY", "SHE", "TOO", "USE", "FRI", "SAT", "SUN", "MON",
            "TUE", "WED", "THU", "JAN", "FEB", "MAR", "APR", "JUN", "JUL", "AUG",
            "SEP", "OCT", "NOV", "DEC", "EST", "PST", "CST", "MST", "GMT", "UTC"
        ])
        
        return !commonWords.contains(code)
    }
}
