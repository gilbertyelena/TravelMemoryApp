//
//  TripSummaryView.swift
//  TravelMemory
//
//  Post-trip recap: where you went, how long, what it held, and what
//  it cost — the "memories" close-out for a completed trip.
//

import SwiftUI

struct TripSummaryView: View {
    let trip: Trip
    @Environment(\.dismiss) private var dismiss

    private var nights: Int {
        trip.hotels.reduce(0) { $0 + $1.nightsCount }
    }

    private var visitedAirports: [String] {
        var seen: Set<String> = []
        var codes: [String] = []
        for flight in trip.flights.sorted(by: { $0.departureTime < $1.departureTime }) {
            for code in [flight.departureAirport, flight.arrivalAirport] where !code.isEmpty {
                if seen.insert(code).inserted {
                    codes.append(code)
                }
            }
        }
        return codes
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.voyagerBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: VoyagerSpacing.stackLarge) {
                        header

                        statsGrid

                        if !visitedAirports.isEmpty {
                            routeStrip
                        }

                        if !trip.budgetText.isEmpty {
                            spendCard
                        }

                        diningRecap
                    }
                    .padding(.horizontal, VoyagerSpacing.marginMain)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Trip Recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.voyagerPrimary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var header: some View {
        let gradient = DestinationGradient.colors(
            for: trip.destination.isEmpty ? trip.name : trip.destination
        )
        return VStack(alignment: .leading, spacing: 8) {
            LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing)
                .frame(height: 4)
                .clipShape(Capsule())

            Text(trip.destination.isEmpty ? trip.name : trip.destination)
                .font(VoyagerFont.headlineLarge)
                .foregroundStyle(Color.voyagerOnSurface)

            Text("\(trip.dateRangeText) · \(trip.durationDays) day\(trip.durationDays == 1 ? "" : "s")")
                .font(VoyagerFont.bodyLarge)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
        }
    }

    private var statsGrid: some View {
        let stats: [(icon: String, value: String, label: String)] = [
            ("airplane.departure", "\(trip.flights.count)", "flight\(trip.flights.count == 1 ? "" : "s")"),
            ("moon.zzz", "\(nights)", "night\(nights == 1 ? "" : "s")"),
            ("fork.knife", "\(trip.dining.count)", "meal\(trip.dining.count == 1 ? "" : "s") out"),
            ("figure.hiking", "\(trip.activities.count)", "activit\(trip.activities.count == 1 ? "y" : "ies")"),
        ]

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                VStack(spacing: 6) {
                    Image(systemName: stat.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(Color.voyagerPrimary)
                    Text(stat.value)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.voyagerOnSurface)
                    Text(stat.label.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .voyagerCard()
            }
        }
    }

    private var routeStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ROUTE")
                .font(VoyagerFont.labelCaps)
                .tracking(1.0)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(visitedAirports.enumerated()), id: \.offset) { index, code in
                        if index > 0 {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.voyagerOutlineVariant)
                        }
                        Text(code)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.voyagerPrimary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .voyagerCard()
    }

    private var spendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOTAL SPEND")
                .font(VoyagerFont.labelCaps)
                .tracking(1.0)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)

            Text(trip.budgetText)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Color.voyagerTertiary)

            ForEach(ItineraryItemType.allCases.map(\.self), id: \.rawValue) { type in
                let spend = trip.timelineItems
                    .filter { $0.itemType == type && $0.cost > 0 }
                    .reduce(into: [String: Double]()) { $0[$1.currencyCode.uppercased(), default: 0] += $1.cost }
                if !spend.isEmpty {
                    HStack {
                        Text(type.label.capitalized)
                            .font(VoyagerFont.bodySmall)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                        Spacer()
                        Text(spend.sorted { $0.key < $1.key }
                            .map { "\(Trip.currencySymbol(for: $0.key))\(VoyagerCostField.format($0.value))" }
                            .joined(separator: " + "))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.voyagerOnSurface)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .voyagerCard()
    }

    @ViewBuilder
    private var diningRecap: some View {
        let places = trip.dining
            .filter { !$0.restaurantName.isEmpty && $0.status != .idea }
            .sorted { $0.reservationTime < $1.reservationTime }
        if !places.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("PLACES YOU ATE")
                    .font(VoyagerFont.labelCaps)
                    .tracking(1.0)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)

                ForEach(Array(places.enumerated()), id: \.offset) { _, place in
                    HStack(spacing: 8) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#FFB868"))
                        Text(place.restaurantName)
                            .font(VoyagerFont.bodySmall)
                            .foregroundStyle(Color.voyagerOnSurface)
                        Spacer()
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .voyagerCard()
        }
    }
}

extension ItineraryItemType: CaseIterable {
    public static var allCases: [ItineraryItemType] {
        [.flight, .hotel, .carRental, .dining, .activity]
    }
}
