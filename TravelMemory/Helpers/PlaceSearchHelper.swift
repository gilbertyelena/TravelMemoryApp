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

@MainActor
class PlaceSearchManager: ObservableObject {
    @Published var results: [MKMapItem] = []
    @Published var isSearching = false
    
    private var searchTask: Task<Void, Never>?
    
    func search(query: String, types: [String] = []) {
        searchTask?.cancel()
        
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            
            let search = MKLocalSearch(request: request)
            do {
                let response = try await search.start()
                if !Task.isCancelled {
                    self.results = Array(response.mapItems.prefix(5))
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
                        .font(VoyagerFont.bodySmallFallback)
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
    /// Search airports by IATA code, city name, or airport name.
    /// Exact code matches are prioritized first.
    static func search(_ query: String) -> [(code: String, city: String, name: String)] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        
        // Exact code match first
        var exactMatches: [(code: String, city: String, name: String)] = []
        var partialMatches: [(code: String, city: String, name: String)] = []
        
        for airport in expanded {
            if airport.code.lowercased() == q {
                exactMatches.append(airport)
            } else if airport.code.lowercased().contains(q) ||
                      airport.city.lowercased().contains(q) ||
                      airport.name.lowercased().contains(q) {
                partialMatches.append(airport)
            }
        }
        
        return Array((exactMatches + partialMatches).prefix(8))
    }
}

