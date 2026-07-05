//
//  GoogleMapsBrowserView.swift
//  TravelMemory
//
//  In-app Google Maps browser for restaurant hunting: full ratings,
//  reviews, and photos — the data Apple's MapKit doesn't expose. When
//  the user opens a place, its name and coordinates are read from the
//  page URL and offered as a one-tap "use this place" action, so
//  nothing has to be memorized and re-searched.
//

import SwiftUI
import WebKit
import CoreLocation

struct GoogleMapsBrowserView: View {
    /// Where to center the initial search (the stay, when known)
    var center: CLLocationCoordinate2D?
    /// Free-text fallback when there's no coordinate yet
    var destination: String = ""
    var searchTerm: String = "restaurants"
    /// Present the "save as idea" action (needs a trip to attach to)
    var allowsShortlist: Bool = false

    var onSelect: (GooglePlaceSelection) -> Void
    var onShortlist: ((GooglePlaceSelection) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var detectedPlace: GooglePlaceSelection?
    @State private var shortlistedName: String?

    private var startURL: URL {
        if let center {
            return URL(string: "https://www.google.com/maps/search/\(encoded(searchTerm))/@\(center.latitude),\(center.longitude),15z")!
        }
        if !destination.isEmpty {
            return URL(string: "https://www.google.com/maps/search/\(encoded("\(searchTerm) in \(destination)"))")!
        }
        return URL(string: "https://www.google.com/maps/search/\(encoded(searchTerm))")!
    }

    private func encoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? text
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                GoogleMapsWebView(startURL: startURL, detectedPlace: $detectedPlace)
                    .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 8) {
                    if let name = shortlistedName {
                        HStack(spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 12))
                            Text("\(name) saved to ideas")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.voyagerPrimaryAccent.opacity(0.92))
                        .clipShape(Capsule())
                        .transition(.opacity)
                    }

                    if let place = detectedPlace {
                        captureBar(for: place)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 10)
                .animation(.easeOut(duration: 0.2), value: detectedPlace)
                .animation(.easeOut(duration: 0.2), value: shortlistedName)
            }
            .navigationTitle("Browse with Ratings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Capture Bar

    private func captureBar(for place: GooglePlaceSelection) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: "#FFB868"))
                Text(place.name)
                    .font(VoyagerFont.bodyLarge)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.voyagerOnSurface)
                    .lineLimit(1)
                Spacer()
            }

            HStack(spacing: 10) {
                if allowsShortlist, onShortlist != nil {
                    Button {
                        onShortlist?(place)
                        shortlistedName = place.name
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            shortlistedName = nil
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "lightbulb")
                                .font(.system(size: 14))
                            Text("IDEA")
                                .font(.system(size: 13, weight: .bold))
                                .tracking(0.6)
                        }
                        .foregroundStyle(Color.voyagerPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.voyagerPrimary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                Button {
                    onSelect(place)
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                        Text("USE THIS PLACE")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(0.6)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(hex: "#FFB868"))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.voyagerCard.opacity(0.97))
                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.voyagerOutlineVariant.opacity(0.25), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .padding(.horizontal, 12)
    }
}

// MARK: - Web View

/// WKWebView that reports the currently viewed Google Maps place by
/// watching URL changes (the page updates its URL to /maps/place/…
/// whenever a place is opened — no scraping involved).
struct GoogleMapsWebView: UIViewRepresentable {
    let startURL: URL
    @Binding var detectedPlace: GooglePlaceSelection?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default() // keep the consent cookie
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black

        context.coordinator.observe(webView)
        webView.load(URLRequest(url: startURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject {
        private let parent: GoogleMapsWebView
        private var observation: NSKeyValueObservation?

        init(_ parent: GoogleMapsWebView) {
            self.parent = parent
        }

        func observe(_ webView: WKWebView) {
            observation = webView.observe(\.url, options: [.new]) { [weak self] _, change in
                guard let self, let url = change.newValue ?? nil else { return }
                let place = GoogleMapsLinkParser.parsePlace(from: url)
                DispatchQueue.main.async {
                    // Only update when it actually changed, to avoid
                    // re-triggering animations on every pan
                    if place != self.parent.detectedPlace {
                        self.parent.detectedPlace = place
                    }
                }
            }
        }

        deinit {
            observation?.invalidate()
        }
    }
}
