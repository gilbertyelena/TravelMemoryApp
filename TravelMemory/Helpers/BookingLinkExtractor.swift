//
//  BookingLinkExtractor.swift
//  TravelMemory
//
//  Fetches a booking URL page and extracts accommodation details
//  from structured data (JSON-LD, Open Graph, meta tags).
//

import Foundation

struct AccommodationDetails {
    var name: String = ""
    var address: String = ""
    var city: String = ""
    var country: String = ""
    var rating: String = ""
    var imageURL: String = ""
    var description: String = ""
    var checkIn: String = ""
    var checkOut: String = ""
    var price: String = ""
    var latitude: Double?
    var longitude: Double?
}

@MainActor
class BookingLinkExtractor: ObservableObject {
    @Published var isLoading = false
    @Published var result: AccommodationDetails?
    @Published var error: String?
    
    func extract(from urlString: String) async {
        var cleanURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanURL.hasPrefix("http") {
            cleanURL = "https://\(cleanURL)"
        }
        
        guard let url = URL(string: cleanURL) else {
            error = "Invalid URL"
            return
        }
        
        isLoading = true
        error = nil
        result = nil
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            // Use a real browser user-agent to get full HTML
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            request.setValue("en-GB,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...399).contains(httpResponse.statusCode) else {
                error = "Page returned an error. Try a different URL."
                isLoading = false
                return
            }
            
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
                error = "Could not read page content"
                isLoading = false
                return
            }
            
            var details = AccommodationDetails()
            
            // 1. Try JSON-LD structured data first (most reliable)
            parseJSONLD(html: html, into: &details)
            
            // 2. Open Graph meta tags
            parseOpenGraph(html: html, into: &details)
            
            // 3. Standard meta tags
            parseMetaTags(html: html, into: &details)
            
            // 4. Page title as final fallback for name
            if details.name.isEmpty {
                parseTitle(html: html, into: &details)
            }
            
            // 5. Site-specific URL parsing as extra fallback
            if details.name.isEmpty {
                parseSiteSpecificURL(url: url, into: &details)
            }
            
            // Build address from components if not already set
            if details.address.isEmpty && !details.city.isEmpty {
                details.address = [details.city, details.country]
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
            }
            
            if details.name.isEmpty {
                error = "Could not find accommodation details on this page. Try pasting booking text instead."
            } else {
                result = details
            }
            
            isLoading = false
            
        } catch {
            self.error = "Network error: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    // MARK: - JSON-LD Parser
    
    private func parseJSONLD(html: String, into details: inout AccommodationDetails) {
        // Find all <script type="application/ld+json"> blocks
        let pattern = "<script[^>]*type\\s*=\\s*[\"']application/ld\\+json[\"'][^>]*>(.*?)</script>"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return }
        
        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let jsonString = nsHTML.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let jsonData = jsonString.data(using: .utf8) else { continue }
            
            // Parse as JSON
            guard let json = try? JSONSerialization.jsonObject(with: jsonData) else { continue }
            
            // Handle array of objects
            let objects: [[String: Any]]
            if let array = json as? [[String: Any]] {
                objects = array
            } else if let single = json as? [String: Any] {
                objects = [single]
            } else {
                continue
            }
            
            for obj in objects {
                let type = (obj["@type"] as? String ?? "").lowercased()
                
                // Check for Hotel, LodgingBusiness, Accommodation, etc.
                let accommodationTypes = ["hotel", "lodgingbusiness", "motel", "hostel", "bedandbreakfast",
                                           "resort", "apartment", "house", "vacationrental", "campground",
                                           "localbusiness", "place"]
                
                let isAccommodation = accommodationTypes.contains { type.lowercased().contains($0.lowercased()) }
                
                if isAccommodation || type.isEmpty {
                    // Name
                    if let name = obj["name"] as? String, !name.isEmpty && details.name.isEmpty {
                        details.name = cleanHTMLEntities(name)
                    }
                    
                    // Address
                    if let addr = obj["address"] as? [String: Any] {
                        let street = addr["streetAddress"] as? String ?? ""
                        let locality = addr["addressLocality"] as? String ?? ""
                        let region = addr["addressRegion"] as? String ?? ""
                        let country = addr["addressCountry"] as? String ?? ""
                        let postalCode = addr["postalCode"] as? String ?? ""
                        
                        let parts = [street, postalCode, locality, region, country]
                            .filter { !$0.isEmpty }
                        
                        if !parts.isEmpty {
                            details.address = parts.joined(separator: ", ")
                        }
                        if !locality.isEmpty { details.city = locality }
                        if !country.isEmpty { details.country = country }
                    } else if let addr = obj["address"] as? String {
                        details.address = addr
                    }
                    
                    // Rating
                    if let rating = obj["starRating"] as? [String: Any],
                       let value = rating["ratingValue"] as? String {
                        details.rating = value
                    } else if let aggregate = obj["aggregateRating"] as? [String: Any],
                              let value = aggregate["ratingValue"] {
                        details.rating = "\(value)"
                    }
                    
                    // Image
                    if let image = obj["image"] as? String {
                        details.imageURL = image
                    } else if let images = obj["image"] as? [String], let first = images.first {
                        details.imageURL = first
                    }
                    
                    // Description
                    if let desc = obj["description"] as? String, details.description.isEmpty {
                        details.description = cleanHTMLEntities(desc)
                    }
                    
                    // Geo coordinates
                    if let geo = obj["geo"] as? [String: Any] {
                        details.latitude = geo["latitude"] as? Double
                        details.longitude = geo["longitude"] as? Double
                    }
                    
                    // Check-in/out times
                    if let checkin = obj["checkinTime"] as? String { details.checkIn = checkin }
                    if let checkout = obj["checkoutTime"] as? String { details.checkOut = checkout }
                    
                    // Price
                    if let offers = obj["priceRange"] as? String { details.price = offers }
                    if let offers = obj["offers"] as? [String: Any],
                       let price = offers["price"] as? String {
                        let currency = offers["priceCurrency"] as? String ?? ""
                        details.price = "\(currency) \(price)"
                    }
                }
                
                // Also check @graph array (used by some sites)
                if let graph = obj["@graph"] as? [[String: Any]] {
                    for item in graph {
                        var tempDetails = AccommodationDetails()
                        let wrappedItem = ["@type": item["@type"] ?? ""] as [String: Any]
                        let mergedItem = item.merging(wrappedItem) { current, _ in current }
                        parseJSONLD(html: "<script type=\"application/ld+json\">\(try! JSONSerialization.data(withJSONObject: mergedItem).base64EncodedString())</script>", into: &tempDetails)
                    }
                }
            }
        }
    }
    
    // MARK: - Open Graph Parser
    
    private func parseOpenGraph(html: String, into details: inout AccommodationDetails) {
        let ogTags: [(String, WritableKeyPath<AccommodationDetails, String>)] = [
            ("og:title", \.name),
            ("og:description", \.description),
            ("og:image", \.imageURL),
        ]
        
        for (property, keyPath) in ogTags {
            if details[keyPath: keyPath].isEmpty {
                if let value = extractMetaContent(from: html, property: property) {
                    var cleaned = value
                    // Clean common suffixes
                    let suffixes = [" - Booking.com", " | Hotels.com", " | Expedia", " - Airbnb",
                                    " - Prices & Reviews", " – Prices & Reviews", " | Agoda",
                                    " from £", " from $", " from €"]
                    for suffix in suffixes {
                        if let range = cleaned.range(of: suffix, options: .caseInsensitive) {
                            cleaned = String(cleaned[..<range.lowerBound])
                        }
                    }
                    details[keyPath: keyPath] = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        // Address from OG tags
        if details.address.isEmpty {
            let locality = extractMetaContent(from: html, property: "og:locality")
            let region = extractMetaContent(from: html, property: "og:region")
            let country = extractMetaContent(from: html, property: "og:country-name")
            let street = extractMetaContent(from: html, property: "og:street-address")
            
            let parts = [street, locality, region, country].compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty {
                details.address = parts.joined(separator: ", ")
            }
            if let loc = locality { details.city = loc }
            if let ctry = country { details.country = ctry }
        }
        
        // Coordinates
        if details.latitude == nil {
            if let lat = extractMetaContent(from: html, property: "og:latitude"),
               let lng = extractMetaContent(from: html, property: "og:longitude"),
               let latD = Double(lat), let lngD = Double(lng) {
                details.latitude = latD
                details.longitude = lngD
            }
            // Also check place:location
            if let lat = extractMetaContent(from: html, property: "place:location:latitude"),
               let lng = extractMetaContent(from: html, property: "place:location:longitude"),
               let latD = Double(lat), let lngD = Double(lng) {
                details.latitude = latD
                details.longitude = lngD
            }
        }
    }
    
    // MARK: - Standard Meta Tags
    
    private func parseMetaTags(html: String, into details: inout AccommodationDetails) {
        if details.description.isEmpty {
            if let desc = extractMetaContent(from: html, property: "description") {
                details.description = cleanHTMLEntities(desc)
            }
        }
    }
    
    // MARK: - Page Title
    
    private func parseTitle(html: String, into details: inout AccommodationDetails) {
        let pattern = "<title[^>]*>(.*?)</title>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
           let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)),
           match.numberOfRanges > 1 {
            var title = (html as NSString).substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Clean suffixes
            let suffixes = [" - Booking.com", " | Hotels.com", " | Expedia", " - Airbnb", " | Agoda"]
            for suffix in suffixes {
                if let range = title.range(of: suffix, options: .caseInsensitive) {
                    title = String(title[..<range.lowerBound])
                }
            }
            details.name = cleanHTMLEntities(title)
        }
    }
    
    // MARK: - Site-Specific URL Parsing
    
    private func parseSiteSpecificURL(url: URL, into details: inout AccommodationDetails) {
        let host = url.host?.lowercased() ?? ""
        let path = url.path
        
        if host.contains("booking.com") {
            let segments = path.components(separatedBy: "/")
            if let slug = segments.last?
                .replacingOccurrences(of: ".html", with: "")
                .replacingOccurrences(of: ".en-gb", with: "")
                .replacingOccurrences(of: ".en-us", with: "") {
                let name = slug.replacingOccurrences(of: "-", with: " ").capitalized
                if name.count > 3 { details.name = name }
            }
        }
        
        if host.contains("hotels.com") {
            let segments = path.components(separatedBy: "/").filter { !$0.isEmpty }
            if segments.count >= 2 {
                let name = segments[1].replacingOccurrences(of: "-", with: " ").capitalized
                if name.count > 3 { details.name = name }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func extractMetaContent(from html: String, property: String) -> String? {
        // Try property="..." content="..." pattern
        let patterns = [
            "property\\s*=\\s*[\"']\(NSRegularExpression.escapedPattern(for: property))[\"'][^>]*content\\s*=\\s*[\"']([^\"']+)[\"']",
            "content\\s*=\\s*[\"']([^\"']+)[\"'][^>]*property\\s*=\\s*[\"']\(NSRegularExpression.escapedPattern(for: property))[\"']",
            "name\\s*=\\s*[\"']\(NSRegularExpression.escapedPattern(for: property))[\"'][^>]*content\\s*=\\s*[\"']([^\"']+)[\"']",
            "content\\s*=\\s*[\"']([^\"']+)[\"'][^>]*name\\s*=\\s*[\"']\(NSRegularExpression.escapedPattern(for: property))[\"']",
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)),
               match.numberOfRanges > 1 {
                return (html as NSString).substring(with: match.range(at: 1))
            }
        }
        return nil
    }
    
    private func cleanHTMLEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
