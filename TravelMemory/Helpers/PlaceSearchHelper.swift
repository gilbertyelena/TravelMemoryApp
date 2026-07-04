//
//  PlaceSearchHelper.swift
//  TravelMemory
//
//  MapKit-powered search for airports and hotels/places.
//  Used by EditFlightView and EditHotelView.
//

import SwiftUI
import MapKit

// MARK: - Place Search Manager

/// Debounced MapKit place search. Optionally biased to a region
/// (restaurant search near the stay) and restricted to points of interest.
@MainActor
class PlaceSearchManager: ObservableObject {
    @Published var results: [MKMapItem] = []
    @Published var isSearching = false

    /// When set, searches are biased to this region and results farther
    /// than ~50 km from its center are dropped.
    var searchRegion: MKCoordinateRegion?
    var pointOfInterestOnly: Bool
    var resultLimit: Int
    /// When set, results are restricted to these POI categories
    /// (e.g. restaurants only, so a name search doesn't return streets).
    var pointOfInterestCategories: [MKPointOfInterestCategory]?

    private var searchTask: Task<Void, Never>?
    private static let maxDistanceFromRegionCenter: CLLocationDistance = 50_000

    init(
        pointOfInterestOnly: Bool = false,
        resultLimit: Int = 5,
        pointOfInterestCategories: [MKPointOfInterestCategory]? = nil
    ) {
        self.pointOfInterestOnly = pointOfInterestOnly
        self.resultLimit = resultLimit
        self.pointOfInterestCategories = pointOfInterestCategories
    }

    /// Distance from the current search region's center, for display.
    func distance(to item: MKMapItem) -> CLLocationDistance? {
        guard let region = searchRegion else { return nil }
        let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let coordinate = item.placemark.coordinate
        return center.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    func search(query: String) {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed
            if pointOfInterestOnly {
                request.resultTypes = .pointOfInterest
            }
            if let categories = pointOfInterestCategories {
                request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
            }
            if let region = searchRegion {
                request.region = region
            }

            do {
                let response = try await MKLocalSearch(request: request).start()
                if !Task.isCancelled {
                    self.results = Array(sortedByDistance(filteredToRegion(response.mapItems)).prefix(resultLimit))
                }
            } catch {
                if !Task.isCancelled {
                    self.results = []
                }
            }
            self.isSearching = false
        }
    }

    /// Immediately search a map region for a category or free-text query,
    /// returning all results. Used by the map browser's "search this area".
    func searchArea(region: MKCoordinateRegion, query: String) {
        searchTask?.cancel()
        isSearching = true

        searchTask = Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = .pointOfInterest
            if let categories = pointOfInterestCategories {
                request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
            }
            request.region = region

            do {
                let response = try await MKLocalSearch(request: request).start()
                if !Task.isCancelled {
                    self.results = response.mapItems
                }
            } catch {
                if !Task.isCancelled {
                    self.results = []
                }
            }
            self.isSearching = false
        }
    }

    func clear() {
        searchTask?.cancel()
        results = []
    }

    private func filteredToRegion(_ items: [MKMapItem]) -> [MKMapItem] {
        guard let region = searchRegion else { return items }
        let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        return items.filter { item in
            let coordinate = item.placemark.coordinate
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            return center.distance(from: location) < Self.maxDistanceFromRegionCenter
        }
    }

    /// Nearest results first when a search region is set.
    private func sortedByDistance(_ items: [MKMapItem]) -> [MKMapItem] {
        guard searchRegion != nil else { return items }
        return items.sorted { (distance(to: $0) ?? .infinity) < (distance(to: $1) ?? .infinity) }
    }
}

// MARK: - Search Suggestion Row

struct SearchSuggestionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(iconColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(VoyagerFont.bodySmall)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.voyagerOnSurface)
                        .lineLimit(1)
                    
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search Results Dropdown

struct SearchResultsDropdown<Content: View>: View {
    let isVisible: Bool
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        if isVisible {
            VStack(spacing: 0) {
                content()
            }
            .background(Color.voyagerSurfaceContainerHigh)
            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                    .stroke(Color.voyagerOutlineVariant.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
    }
}

// MARK: - Common Airport Codes (offline database)

struct AirportDatabase {
    typealias Airport = (code: String, city: String, name: String)

    /// Search airports by IATA code, city name, or airport name.
    /// Diacritic-insensitive ("munchen" finds Munich) and ranked:
    /// exact code > code prefix > city prefix > name prefix > contains.
    static func search(_ query: String) -> [Airport] {
        let q = normalize(query)
        guard !q.isEmpty else { return [] }

        var ranked: [(rank: Int, airport: Airport)] = []

        for airport in expanded {
            let code = normalize(airport.code)
            let city = normalize(airport.city)
            let name = normalize(airport.name)

            let rank: Int
            if code == q {
                rank = 0
            } else if code.hasPrefix(q) {
                rank = 1
            } else if city.hasPrefix(q) {
                rank = 2
            } else if name.hasPrefix(q) {
                rank = 3
            } else if city.contains(q) || name.contains(q) {
                rank = 4
            } else {
                continue
            }
            ranked.append((rank, airport))
        }

        return ranked
            .sorted { $0.rank < $1.rank }
            .prefix(8)
            .map(\.airport)
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: Recently used airports

    private static let recentsKey = "recentAirportCodes"
    private static let maxRecents = 5

    /// Airports the user picked recently — shown before typing.
    static func recents() -> [Airport] {
        let codes = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        return codes.compactMap { code in
            expanded.first { $0.code == code }
        }
    }

    /// Record a picked airport so it surfaces at the top next time.
    static func recordRecent(code: String) {
        var codes = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        codes.removeAll { $0 == code }
        codes.insert(code, at: 0)
        UserDefaults.standard.set(Array(codes.prefix(maxRecents)), forKey: recentsKey)
    }
}

