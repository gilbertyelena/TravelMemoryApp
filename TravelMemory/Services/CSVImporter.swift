//
//  CSVImporter.swift
//  TravelMemory
//
//  Imports a spreadsheet itinerary (CSV) — the migration path for
//  anyone maintaining trips in Excel/Numbers/Sheets. Column meanings
//  are detected from the header row; each data row becomes an
//  itinerary item staged through the normal review screen.
//

import Foundation

struct CSVImporter {

    // MARK: - CSV Tokenizer (RFC 4180-ish)

    /// Parses CSV text into rows of fields. Handles quoted fields,
    /// escaped quotes, embedded commas/newlines, and ;-delimited
    /// exports (common from European Excel locales).
    static func rows(from text: String) -> [[String]] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Choose delimiter by frequency outside quotes in the first line
        let firstLine = normalized.prefix(while: { $0 != "\n" })
        let delimiter: Character = firstLine.filter { $0 == ";" }.count > firstLine.filter { $0 == "," }.count ? ";" : ","

        var result: [[String]] = []
        var field = ""
        var row: [String] = []
        var insideQuotes = false
        var iterator = normalized.makeIterator()
        var pending: Character? = nil

        func nextChar() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }

        while let char = nextChar() {
            if insideQuotes {
                if char == "\"" {
                    if let peek = iterator.next() {
                        if peek == "\"" {
                            field.append("\"")
                        } else {
                            insideQuotes = false
                            pending = peek
                        }
                    } else {
                        insideQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else {
                switch char {
                case "\"":
                    insideQuotes = true
                case delimiter:
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    field = ""
                    if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespaces).isEmpty) {
                        result.append(row)
                    }
                    row = []
                default:
                    field.append(char)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            result.append(row)
        }
        return result
    }

    // MARK: - Column Detection

    enum Column {
        case date, time, type, name, location, cost, currency, notes, confirmation, endDate
    }

    /// Maps header cells to column meanings by fuzzy name matching.
    static func detectColumns(in header: [String]) -> [Int: Column] {
        var mapping: [Int: Column] = [:]
        for (index, raw) in header.enumerated() {
            let cell = raw.lowercased().trimmingCharacters(in: .whitespaces)
            let column: Column?
            switch true {
            case cell.contains("end") && (cell.contains("date") || cell.contains("day")),
                 cell.contains("check-out"), cell.contains("checkout"), cell.contains("until"):
                column = .endDate
            case cell.contains("date") || cell == "day" || cell.contains("when") || cell.contains("check-in") || cell.contains("checkin"):
                column = .date
            case cell.contains("time") || cell.contains("hour"):
                column = .time
            case cell.contains("type") || cell.contains("category") || cell.contains("kind"):
                column = .type
            case cell.contains("name") || cell.contains("title") || cell.contains("what")
                 || cell.contains("description") || cell.contains("item") || cell.contains("activity"):
                column = .name
            case cell.contains("location") || cell.contains("where") || cell.contains("place")
                 || cell.contains("address") || cell.contains("city"):
                column = .location
            case cell.contains("cost") || cell.contains("price") || cell.contains("amount")
                 || cell.contains("budget") || cell.contains("paid"):
                column = .cost
            case cell.contains("currency"):
                column = .currency
            case cell.contains("note") || cell.contains("comment") || cell.contains("detail"):
                column = .notes
            case cell.contains("confirmation") || cell.contains("booking ref")
                 || cell.contains("reference") || cell == "ref" || cell.contains("pnr"):
                column = .confirmation
            default:
                column = nil
            }
            if let column, !mapping.values.contains(column) || column == .name {
                mapping[index] = column
            }
        }
        return mapping
    }

    // MARK: - Import

    static func parse(_ text: String) -> EmailParser.ParseResult {
        var result = EmailParser.ParseResult()
        let allRows = rows(from: text)

        guard allRows.count >= 1 else {
            result.issues.append("The file appears to be empty")
            result.overallConfidence = 0.1
            return result
        }

        var mapping = detectColumns(in: allRows[0])
        var dataRows = Array(allRows.dropFirst())

        // No usable header? Assume date, time, type, name, location, cost
        if mapping[safeFind: .date] == nil && mapping[safeFind: .name] == nil {
            mapping = [0: .date, 1: .time, 2: .type, 3: .name, 4: .location, 5: .cost]
            dataRows = allRows
        }

        var skipped = 0
        for row in dataRows {
            if !importRow(row, mapping: mapping, into: &result) {
                skipped += 1
            }
        }

        let importedCount = result.flights.count + result.hotels.count + result.carRentals.count
            + result.dining.count + result.activities.count

        if importedCount == 0 {
            result.issues.append("No rows could be understood — check that the sheet has date and name columns")
            result.overallConfidence = 0.1
            return result
        }
        if skipped > 0 {
            result.issues.append("\(skipped) row\(skipped == 1 ? "" : "s") skipped (no date or name)")
        }

        result.overallConfidence = 0.85
        return result
    }

    @discardableResult
    private static func importRow(_ row: [String], mapping: [Int: Column], into result: inout EmailParser.ParseResult) -> Bool {
        func value(_ column: Column) -> String {
            for (index, mapped) in mapping where mapped == column {
                if index < row.count {
                    return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return ""
        }

        let name = value(.name)
        let dateText = value(.date)
        let date = parseDate(dateText, time: value(.time))
        // A row is only meaningful with a real name or a parseable date —
        // otherwise prose accidentally read as CSV becomes phantom items.
        guard !name.isEmpty || date != nil else { return false }
        let endDate = parseDate(value(.endDate), time: "")
        let location = value(.location)
        let notes = value(.notes)
        let confirmation = value(.confirmation).uppercased()
        let (cost, currencyFromCost) = parseCost(value(.cost))
        let currency = value(.currency).uppercased().isEmpty ? currencyFromCost : value(.currency).uppercased()

        let typeHint = (value(.type) + " " + name).lowercased()

        if typeHint.contains("flight") || typeHint.contains("plane") || typeHint.contains("fly") {
            var flight = EmailParser.parseFlights(from: "\(name)\n\(location)").first
                ?? EmailParser.FlightParseData(
                    airline: "", flightNumber: "", departureAirport: "", departureCity: "",
                    arrivalAirport: "", arrivalCity: "", departureTime: nil, arrivalTime: nil,
                    gate: "", seat: "", confirmationCode: "", confidence: 0.8
                )
            flight.departureTime = date
            flight.arrivalTime = endDate
            if flight.confirmationCode.isEmpty { flight.confirmationCode = confirmation }
            flight.confidence = 0.85
            flight.cost = cost
            flight.currencyCode = currency
            result.flights.append(flight)
        } else if typeHint.contains("hotel") || typeHint.contains("stay") || typeHint.contains("accommodation")
                    || typeHint.contains("apartment") || typeHint.contains("airbnb") || typeHint.contains("lodging") {
            var hotel = EmailParser.HotelParseData(
                hotelName: name, address: location,
                checkIn: date, checkOut: endDate,
                confirmationCode: confirmation, confidence: 0.85
            )
            hotel.cost = cost
            hotel.currencyCode = currency
            result.hotels.append(hotel)
        } else if typeHint.contains("car") || typeHint.contains("rental") || typeHint.contains("hire") {
            var car = EmailParser.CarRentalParseData(
                company: name, vehicleType: "",
                pickupTime: date, dropoffTime: endDate,
                pickupLocation: location, confirmationCode: confirmation,
                isPrepaid: false, confidence: 0.85
            )
            car.cost = cost
            car.currencyCode = currency
            result.carRentals.append(car)
        } else if typeHint.contains("dinner") || typeHint.contains("lunch") || typeHint.contains("restaurant")
                    || typeHint.contains("dining") || typeHint.contains("brunch") || typeHint.contains("food") {
            var dining = EmailParser.DiningParseData(
                restaurantName: name, address: location,
                reservationTime: date, notes: notes, confidence: 0.85
            )
            dining.cost = cost
            dining.currencyCode = currency
            result.dining.append(dining)
        } else {
            var activity = EmailParser.ActivityParseData(
                activityName: name.isEmpty ? "Imported item" : name,
                location: location,
                startTime: date, endTime: endDate,
                notes: notes, confidence: 0.8
            )
            activity.cost = cost
            activity.currencyCode = currency
            result.activities.append(activity)
        }
        return true
    }

    // MARK: - Field Parsing

    /// Tries common spreadsheet date formats; attaches an optional time.
    static func parseDate(_ dateText: String, time timeText: String) -> Date? {
        let text = dateText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        let formats = [
            "yyyy-MM-dd", "dd/MM/yyyy", "d/M/yyyy", "MM/dd/yyyy",
            "d MMM yyyy", "MMM d yyyy", "MMM d, yyyy", "d.M.yyyy", "dd.MM.yyyy",
            "d MMMM yyyy", "EEE d MMM yyyy", "EEEE d MMMM yyyy",
        ]
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")

        var parsed: Date?
        for format in formats {
            fmt.dateFormat = format
            if let date = fmt.date(from: text) {
                parsed = date
                break
            }
        }
        guard var date = parsed else { return nil }

        // Attach the time column, or one embedded in the date cell
        let timeSource = timeText.isEmpty ? text : timeText
        if let range = timeSource.range(of: #"\b(\d{1,2}):(\d{2})\s*(am|pm|AM|PM)?\b"#, options: .regularExpression) {
            let timeString = String(timeSource[range])
            let timeFmt = DateFormatter()
            timeFmt.locale = Locale(identifier: "en_US_POSIX")
            timeFmt.dateFormat = timeString.lowercased().contains("m") ? "h:mm a" : "HH:mm"
            if let timeDate = timeFmt.date(from: timeString) {
                let cal = Calendar.current
                let hour = cal.component(.hour, from: timeDate)
                let minute = cal.component(.minute, from: timeDate)
                date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
            }
        }
        return date
    }

    /// "£123.45", "EUR 99", "1,234" → amount + inferred currency code
    static func parseCost(_ text: String) -> (amount: Double, currency: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return (0, "") }

        var currency = ""
        switch true {
        case trimmed.contains("£"): currency = "GBP"
        case trimmed.contains("€"): currency = "EUR"
        case trimmed.contains("$"): currency = "USD"
        case trimmed.contains("¥"): currency = "JPY"
        default:
            if let match = trimmed.range(of: #"^[A-Za-z]{3}\b"#, options: .regularExpression) {
                currency = String(trimmed[match]).uppercased()
            }
        }

        let numberText = trimmed.filter { $0.isNumber || $0 == "." || $0 == "," }
        return (VoyagerCostField.parse(String(numberText)), currency)
    }
}

// Helper: find a column index by meaning
private extension Dictionary where Key == Int, Value == CSVImporter.Column {
    subscript(safeFind column: CSVImporter.Column) -> Int? {
        first { $0.value == column }?.key
    }
}
