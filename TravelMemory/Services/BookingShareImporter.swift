//
//  BookingShareImporter.swift
//  TravelMemory
//
//  Turns a Booking.com property link — shared from their app — into a
//  hotel item. The URL slug alone gives a usable name offline; when the
//  network cooperates, the property page enriches it with the exact
//  title and street address.
//

import Foundation

struct BookingShareImporter {

    /// True when shared text contains a Booking.com link.
    static func isBookingLink(_ text: String) -> Bool {
        text.lowercased().contains("booking.com")
    }

    /// Booking.com flight links carry no itinerary data — no numbers,
    /// no times — so they can't be imported and must not be mistaken
    /// for hotel pages.
    static func isFlightLink(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("flights.booking.com") || lowered.contains("booking.com/flights")
    }

    /// Builds a hotel parse from shared Booking.com content.
    static func hotelImport(from text: String) async -> EmailParser.HotelParseData? {
        guard !isFlightLink(text), let url = firstURL(in: text) else { return nil }

        // Follow share-shortlink redirects (booking.com/Share-xxxx)
        var resolved = url
        if !url.path.lowercased().contains("/hotel/") {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let finalURL = response.url {
                resolved = finalURL
            }
        }

        // Baseline: hotel name from the URL slug — works offline
        var hotel = EmailParser.HotelParseData(
            hotelName: nameFromSlug(of: resolved) ?? "",
            address: "",
            checkIn: nil,
            checkOut: nil,
            confirmationCode: "",
            confidence: 0.8
        )

        // Enrichment: fetch the property page for the exact name/address
        if let enriched = await pageDetails(of: resolved) {
            if !enriched.name.isEmpty { hotel.hotelName = enriched.name }
            hotel.address = enriched.address
        }

        guard !hotel.hotelName.isEmpty else { return nil }
        return hotel
    }

    // MARK: - Pieces

    static func firstURL(in text: String) -> URL? {
        guard let range = text.range(of: #"https?://\S+"#, options: .regularExpression) else {
            return nil
        }
        return URL(string: String(text[range]))
    }

    /// "/hotel/de/vier-jahreszeiten-kempinski-muenchen.html" →
    /// "Vier Jahreszeiten Kempinski Muenchen"
    static func nameFromSlug(of url: URL) -> String? {
        guard let hotelIndex = url.pathComponents.firstIndex(of: "hotel"),
              url.pathComponents.count > hotelIndex + 2 else {
            return nil
        }
        let slug = url.pathComponents[hotelIndex + 2]
            .replacingOccurrences(of: ".html", with: "")
            .replacingOccurrences(of: #"\.[a-z]{2}(-[a-z]{2})?$"#, with: "", options: .regularExpression)
        let name = slug.replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.count > 2 ? $0.capitalized : String($0) }
            .joined(separator: " ")
        return name.count > 3 ? name : nil
    }

    private static func pageDetails(of url: URL) async -> (name: String, address: String)? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        var name = ""
        // og:title first, <title> fallback; strip the marketing suffixes
        for pattern in [
            #"property\s*=\s*"og:title"[^>]*content\s*=\s*"([^"]+)""#,
            #"<title[^>]*>([^<]+)</title>"#,
        ] {
            if let range = html.range(of: pattern, options: .regularExpression) {
                let match = String(html[range])
                if let contentRange = match.range(of: #"(?<=["'>])[^"'<>]{3,120}"#, options: .regularExpression) {
                    name = String(match[contentRange])
                    break
                }
            }
        }
        for suffix in [" - Booking.com", " | Booking.com", ", Munich", " (updated prices"] {
            if let range = name.range(of: suffix, options: .caseInsensitive) {
                name = String(name[..<range.lowerBound])
            }
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Street address from the embedded JSON-LD, if present
        var address = ""
        if let streetRange = html.range(of: #""streetAddress"\s*:\s*"([^"]+)""#, options: .regularExpression) {
            let match = String(html[streetRange])
            address = match.components(separatedBy: "\"").dropLast().last ?? ""
        }
        if let cityRange = html.range(of: #""addressLocality"\s*:\s*"([^"]+)""#, options: .regularExpression) {
            let match = String(html[cityRange])
            let city = match.components(separatedBy: "\"").dropLast().last ?? ""
            if !city.isEmpty {
                address = address.isEmpty ? city : "\(address), \(city)"
            }
        }

        return (name, address)
    }
}
