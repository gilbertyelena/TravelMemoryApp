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
    
    /// Result of parsing an email
    struct ParseResult {
        var flights: [FlightParseData] = []
        var hotels: [HotelParseData] = []
        var carRentals: [CarRentalParseData] = []
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
    }
    
    struct HotelParseData {
        var hotelName: String
        var address: String
        var checkIn: Date?
        var checkOut: Date?
        var confirmationCode: String
        var confidence: Double
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
            let flight = parseFlightDetails(from: combinedText)
            result.flights.append(flight)
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
        let flightKeywords = [
            "flight confirmation", "booking confirmation", "e-ticket",
            "itinerary receipt", "boarding pass", "flight reservation",
            "your trip", "flight details", "air reservation",
            "ticket confirmation"
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
        
        return subjectMatch || senderMatch
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
    
    private static func parseFlightDetails(from text: String) -> FlightParseData {
        var flight = FlightParseData(
            airline: "", flightNumber: "",
            departureAirport: "", departureCity: "",
            arrivalAirport: "", arrivalCity: "",
            departureTime: nil, arrivalTime: nil,
            gate: "", seat: "",
            confirmationCode: "", confidence: 0.5
        )
        
        var confidenceBoost = 0.0
        
        // Extract flight number (e.g. "LH411", "UA 1234", "DL 456")
        if let match = firstMatch(in: text, pattern: #"([A-Z]{2})\s?(\d{1,4})"#) {
            let components = match.components(separatedBy: " ").joined()
            if let codeMatch = firstMatch(in: components, pattern: #"([A-Z]{2})(\d+)"#) {
                flight.flightNumber = codeMatch
                confidenceBoost += 0.1
            }
        }
        
        // Extract airline name
        let airlines = [
            "Lufthansa": "LH", "United": "UA", "Delta": "DL",
            "American Airlines": "AA", "Southwest": "WN",
            "British Airways": "BA", "Air France": "AF",
            "KLM": "KL", "Emirates": "EK", "Virgin Atlantic": "VS",
            "JetBlue": "B6", "Alaska Airlines": "AS", "Qantas": "QF",
            "Ryanair": "FR", "EasyJet": "U2", "Spirit": "NK"
        ]
        for (name, code) in airlines {
            if text.localizedCaseInsensitiveContains(name) {
                flight.airline = name
                if flight.flightNumber.isEmpty || !flight.flightNumber.hasPrefix(code) {
                    // Keep found flight number but set airline
                }
                confidenceBoost += 0.1
                break
            }
        }
        
        // Extract airport codes (3-letter IATA codes)
        let airportPattern = #"\b([A-Z]{3})\b"#
        let airports = allMatches(in: text.uppercased(), pattern: airportPattern)
            .filter { isLikelyAirportCode($0) }
        
        if airports.count >= 2 {
            flight.departureAirport = airports[0]
            flight.arrivalAirport = airports[1]
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
                // Try to get full hotel name (brand + location)
                if let fullName = firstMatch(in: text, pattern: "\(brand)[\\w\\s]*(?=[\\n,\\.])") {
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
            if let match = firstMatch(in: text, pattern: #"(?:Hotel|Inn|Resort|Lodge)\s+[\w\s]+(?=[\n,\.])"#) {
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
        
        // Check if it looks like it has flight info
        let hasAirportCodes = allMatches(in: combinedText.uppercased(), pattern: #"\b([A-Z]{3})\b"#)
            .filter { isLikelyAirportCode($0) }
            .count >= 2
        let hasFlightNumber = firstMatch(in: combinedText, pattern: #"[A-Z]{2}\s?\d{1,4}"#) != nil
        
        if hasAirportCodes || hasFlightNumber {
            result.flights.append(parseFlightDetails(from: combinedText))
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
        // Normalize whitespace
        cleaned = cleaned.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        guard let matchRange = Range(match.range, in: text) else { return nil }
        return String(text[matchRange])
    }
    
    private static func allMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap {
            guard let matchRange = Range($0.range, in: text) else { return nil }
            return String(text[matchRange])
        }
    }
    
    private static func extractDates(from text: String) -> [Date] {
        var dates: [Date] = []
        
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
        
        for (pattern, format) in formatters {
            let matches = allMatches(in: text, pattern: pattern)
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US")
            fmt.dateFormat = format
            for match in matches {
                let cleanMatch = match.replacingOccurrences(of: ",", with: "")
                if let date = fmt.date(from: cleanMatch) {
                    dates.append(date)
                }
            }
        }
        
        // Also try time extraction for the found dates
        let timePattern = #"\b(\d{1,2}:\d{2}\s*(?:AM|PM|am|pm)?)\b"#
        let times = allMatches(in: text, pattern: timePattern)
        
        if !dates.isEmpty && !times.isEmpty {
            let timeFmt = DateFormatter()
            timeFmt.locale = Locale(identifier: "en_US")
            
            for (i, time) in times.prefix(dates.count).enumerated() {
                let cleanTime = time.trimmingCharacters(in: .whitespaces)
                timeFmt.dateFormat = cleanTime.contains("M") || cleanTime.contains("m") ? "h:mm a" : "HH:mm"
                if let timeDate = timeFmt.date(from: cleanTime) {
                    let cal = Calendar.current
                    let hour = cal.component(.hour, from: timeDate)
                    let minute = cal.component(.minute, from: timeDate)
                    if i < dates.count {
                        dates[i] = cal.date(bySettingHour: hour, minute: minute, second: 0, of: dates[i]) ?? dates[i]
                    }
                }
            }
        }
        
        return dates.sorted()
    }
    
    private static func extractConfirmationCode(from text: String) -> String? {
        // Common patterns: "Confirmation: ABC123", "Booking Ref: XYZ789", "PNR: ABCDE"
        let patterns = [
            #"(?:confirmation|booking\s*(?:ref|reference|number|code)|pnr|record\s*locator|reservation)\s*(?:#|:|\s)\s*([A-Z0-9]{5,8})"#,
            #"(?:confirmation|booking)\s*(?:#|:)\s*(\d{6,12})"#,
        ]
        
        for pattern in patterns {
            if let match = firstMatch(in: text.uppercased(), pattern: pattern) {
                // Extract just the code part
                let components = match.components(separatedBy: CharacterSet.alphanumerics.inverted)
                if let code = components.last, code.count >= 5 {
                    return code
                }
            }
        }
        
        return nil
    }
    
    /// Checks if a 3-letter code is likely an IATA airport code
    private static func isLikelyAirportCode(_ code: String) -> Bool {
        let commonCodes = Set([
            "JFK", "LAX", "ORD", "SFO", "MIA", "ATL", "DFW", "DEN", "SEA", "BOS",
            "LHR", "LGW", "CDG", "FRA", "MUC", "AMS", "FCO", "MAD", "BCN", "IST",
            "DXB", "SIN", "HKG", "NRT", "HND", "ICN", "BKK", "SYD", "MEL", "AKL",
            "EWR", "IAD", "IAH", "PHX", "MSP", "DTW", "CLT", "MCO", "TPA", "PHL",
            "ZRH", "VIE", "CPH", "OSL", "ARN", "HEL", "DUB", "EDI", "LIS", "GVA",
            "YYZ", "YVR", "MEX", "GRU", "EZE", "BOG", "SCL", "LIM", "PTY", "CUN"
        ])
        
        // If it's a known code, definitely an airport
        if commonCodes.contains(code) { return true }
        
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
