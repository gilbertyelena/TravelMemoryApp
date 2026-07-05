//
//  GoogleMapsLinkParser.swift
//  TravelMemory
//
//  Extracts a place (name + coordinates) from Google Maps URLs — both
//  the in-app browser's address changes and pasted share links. This is
//  what lets the app capture a restaurant the user found on Google
//  without retyping or re-searching it.
//

import Foundation
import CoreLocation

struct GooglePlaceSelection: Equatable {
    var name: String
    var latitude: Double?
    var longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct GoogleMapsLinkParser {

    /// True for anything that looks like a Google Maps link (including
    /// the maps.app.goo.gl short links from the share sheet).
    static func isMapsLink(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("google.") && lowered.contains("/maps")
            || lowered.contains("maps.app.goo.gl")
            || lowered.contains("goo.gl/maps")
    }

    /// Parses a full (already-expanded) Google Maps URL into a place.
    ///
    /// Handles:
    ///   /maps/place/Tantris/@48.163,11.586,17z/data=...!3d48.1632!4d11.5865...
    ///   /maps/search/?api=1&query=Tantris+Munich
    ///   /maps?q=Tantris,+Munich
    static func parsePlace(from url: URL) -> GooglePlaceSelection? {
        let urlString = url.absoluteString

        var name: String?
        var latitude: Double?
        var longitude: Double?

        // Place name from the /maps/place/<name>/ path segment
        if let match = urlString.range(of: #"/maps/place/([^/@?]+)"#, options: .regularExpression) {
            let segment = String(urlString[match]).replacingOccurrences(of: "/maps/place/", with: "")
            name = decodePlaceName(segment)
        }

        // Most precise pin: the !3d<lat>!4d<lng> pair in the data blob
        if let latRange = urlString.range(of: #"!3d(-?\d+\.\d+)"#, options: .regularExpression),
           let lngRange = urlString.range(of: #"!4d(-?\d+\.\d+)"#, options: .regularExpression) {
            latitude = Double(urlString[latRange].dropFirst(3))
            longitude = Double(urlString[lngRange].dropFirst(3))
        }

        // Fall back to the viewport center @lat,lng
        if latitude == nil,
           let match = urlString.range(of: #"@(-?\d+\.\d+),(-?\d+\.\d+)"#, options: .regularExpression) {
            let pair = String(urlString[match]).dropFirst().components(separatedBy: ",")
            if pair.count >= 2 {
                latitude = Double(pair[0])
                longitude = Double(pair[1])
            }
        }

        // Query-style links carry the name in q= / query=
        if name == nil, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            for key in ["q", "query"] {
                if let value = components.queryItems?.first(where: { $0.name == key })?.value,
                   !value.isEmpty,
                   Double(value.components(separatedBy: ",").first ?? "") == nil {
                    name = decodePlaceName(value)
                    break
                }
            }
        }

        guard let name, !name.isEmpty else { return nil }
        return GooglePlaceSelection(name: name, latitude: latitude, longitude: longitude)
    }

    /// Expands a maps.app.goo.gl / goo.gl short link by following its
    /// redirect, then parses the destination.
    static func expandAndParse(_ text: String) async -> GooglePlaceSelection? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Pull the first URL out of surrounding share-sheet text
        guard let urlRange = trimmed.range(of: #"https?://\S+"#, options: .regularExpression),
              let url = URL(string: String(trimmed[urlRange])) else {
            return nil
        }

        // Already a full link? Parse directly.
        if let place = parsePlace(from: url) {
            return place
        }

        // Short link: follow redirects; the final URL is the full place link
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let finalURL = response.url else {
            return nil
        }
        return parsePlace(from: finalURL)
    }

    /// "Tantris+Restaurant" / "Tantris%20Restaurant" → "Tantris Restaurant"
    private static func decodePlaceName(_ segment: String) -> String {
        let plusDecoded = segment.replacingOccurrences(of: "+", with: " ")
        return (plusDecoded.removingPercentEncoding ?? plusDecoded)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
