//
//  TripsListView.swift
//  TravelMemory
//
//  Landing page: shows all trips with rich visual cards,
//  "Next Up" smart banner, and staggered entrance animations.
//

import SwiftUI
import SwiftData

struct TripsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.startDate, order: .forward) private var trips: [Trip]
    
    @State private var showCreateTrip = false
    @State private var showEmailInput = false
    @State private var selectedTrip: Trip?
    @State private var appeared = false
    
    /// The next upcoming event across all trips
    private var nextUpEvent: NextUpInfo? {
        let now = Date()
        var candidates: [NextUpInfo] = []
        
        for trip in trips where trip.status != .completed {
            // Check trip start
            if trip.startDate > now {
                candidates.append(NextUpInfo(
                    trip: trip,
                    icon: "airplane.departure",
                    title: "Trip begins",
                    subtitle: trip.destination.isEmpty ? trip.name : trip.destination,
                    date: trip.startDate,
                    accentColor: .voyagerPrimaryAccent
                ))
            }
            
            // Check upcoming flights
            for flight in trip.flights where flight.departureTime > now {
                candidates.append(NextUpInfo(
                    trip: trip,
                    icon: "airplane.departure",
                    title: "\(flight.airline) \(flight.flightNumber)",
                    subtitle: "\(flight.departureAirport) → \(flight.arrivalAirport)",
                    date: flight.departureTime,
                    accentColor: .voyagerPrimaryAccent
                ))
            }
            
            // Check upcoming hotel check-ins
            for hotel in trip.hotels where hotel.checkInDate > now {
                candidates.append(NextUpInfo(
                    trip: trip,
                    icon: "bed.double",
                    title: "Check-in",
                    subtitle: hotel.hotelName,
                    date: hotel.checkInDate,
                    accentColor: .voyagerTertiary
                ))
            }
            
            // Check upcoming car pickups
            for car in trip.carRentals where car.pickupTime > now {
                candidates.append(NextUpInfo(
                    trip: trip,
                    icon: "car",
                    title: "Car Pickup",
                    subtitle: car.company,
                    date: car.pickupTime,
                    accentColor: .voyagerPrimary
                ))
            }
        }
        
        return candidates.sorted(by: { $0.date < $1.date }).first
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.voyagerBackground.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Top Bar
                        VoyagerTopBar(showNotificationBadge: false, notificationCount: 0)
                        
                        // Page Title
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your Trips")
                                .font(VoyagerFont.headlineLarge)
                                .foregroundStyle(Color.voyagerOnBackground)
                            Text("\(trips.count) trip\(trips.count == 1 ? "" : "s")")
                                .font(VoyagerFont.bodySmall)
                                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                        }
                        .padding(.horizontal, VoyagerSpacing.marginMain)
                        .padding(.top, VoyagerSpacing.stackLarge)
                        
                        // ━━ NEXT UP BANNER ━━
                        if let nextUp = nextUpEvent {
                            nextUpBanner(nextUp)
                                .padding(.horizontal, VoyagerSpacing.marginMain)
                                .padding(.top, VoyagerSpacing.stackMedium)
                                .staggeredAppear(index: 0, appeared: appeared)
                        }
                        
                        // Action buttons
                        HStack(spacing: 12) {
                            Button {
                                showCreateTrip = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 16))
                                    Text("NEW TRIP")
                                }
                                .font(VoyagerFont.labelCaps)
                                .tracking(0.6)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.voyagerPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                            }
                            
                            Button {
                                showEmailInput = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "envelope.open")
                                        .font(.system(size: 16))
                                    Text("FROM EMAIL")
                                }
                                .font(VoyagerFont.labelCaps)
                                .tracking(0.6)
                                .foregroundStyle(Color.voyagerPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.voyagerPrimary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                                .overlay(
                                    RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                                        .stroke(Color.voyagerPrimary.opacity(0.3), lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal, VoyagerSpacing.marginMain)
                        .padding(.top, VoyagerSpacing.stackLarge)
                        .staggeredAppear(index: 1, appeared: appeared)
                        
                        // Trip cards
                        if trips.isEmpty {
                            emptyState
                                .padding(.top, 40)
                                .staggeredAppear(index: 2, appeared: appeared)
                        } else {
                            VStack(spacing: VoyagerSpacing.stackMedium) {
                                ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                                    Button {
                                        selectedTrip = trip
                                    } label: {
                                        tripCard(trip)
                                    }
                                    .buttonStyle(.plain)
                                    .staggeredAppear(index: index + 2, appeared: appeared)
                                }
                            }
                            .padding(.horizontal, VoyagerSpacing.marginMain)
                            .padding(.top, VoyagerSpacing.stackLarge)
                        }
                    }
                    .padding(.bottom, 120)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $selectedTrip) { trip in
                TripDetailView(trip: trip)
            }
            .sheet(isPresented: $showCreateTrip) {
                EditTripView(mode: .create)
            }
            .sheet(isPresented: $showEmailInput) {
                EmailInputView()
            }
            .onAppear {
                withAnimation {
                    appeared = true
                }
            }
        }
    }
    
    // MARK: - Next Up Banner
    
    private func nextUpBanner(_ info: NextUpInfo) -> some View {
        Button {
            selectedTrip = info.trip
        } label: {
            HStack(spacing: 14) {
                // Accent icon with glow
                ZStack {
                    Circle()
                        .fill(info.accentColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: info.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(info.accentColor)
                        .voyagerGlow(color: info.accentColor, radius: 10, opacity: 0.4)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("NEXT UP")
                            .font(VoyagerFont.labelCaps)
                            .tracking(1.0)
                            .foregroundStyle(info.accentColor)
                        
                        Text("•")
                            .foregroundStyle(Color.voyagerOutlineVariant)
                        
                        Text(TripCountdown.text(from: info.date).uppercased())
                            .font(VoyagerFont.labelCaps)
                            .tracking(0.6)
                            .foregroundStyle(TripCountdown.color(from: info.date))
                    }
                    
                    Text(info.title)
                        .font(VoyagerFont.bodyLarge)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.voyagerOnSurface)
                    
                    Text(info.subtitle)
                        .font(VoyagerFont.bodySmall)
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(info.accentColor.opacity(0.6))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: VoyagerRadius.large)
                    .fill(Color.voyagerSurfaceContainerHigh)
                    .overlay(
                        RoundedRectangle(cornerRadius: VoyagerRadius.large)
                            .stroke(info.accentColor.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: info.accentColor.opacity(0.1), radius: 16, y: 4)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.voyagerPrimary.opacity(0.08))
                    .frame(width: 120, height: 120)
                Circle()
                    .fill(Color.voyagerPrimary.opacity(0.05))
                    .frame(width: 160, height: 160)
                Image(systemName: "airplane.circle")
                    .font(.system(size: 56, weight: .ultraLight))
                    .foregroundStyle(Color.voyagerPrimary)
                    .symbolEffect(.pulse, options: .repeating)
            }
            
            VStack(spacing: 8) {
                Text("No Trips Yet")
                    .font(VoyagerFont.headlineMedium)
                    .foregroundStyle(Color.voyagerOnSurface)
                Text("Create a trip manually or forward\na booking confirmation email")
                    .font(VoyagerFont.bodySmall)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Trip Card (Upgraded)
    
    private func tripCard(_ trip: Trip) -> some View {
        let gradientColors = DestinationGradient.colors(for: trip.destination.isEmpty ? trip.name : trip.destination)
        let totalPackingItems = trip.packingCategories.flatMap(\.items).count
        let packedItems = trip.packingCategories.flatMap(\.items).filter(\.isPacked).count
        let packingProgress = totalPackingItems > 0 ? Double(packedItems) / Double(totalPackingItems) : 0
        
        return VStack(alignment: .leading, spacing: 0) {
            // ━━ Gradient Header Strip ━━
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 6)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: VoyagerRadius.large,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: VoyagerRadius.large
                    )
                )
            }
            
            // ━━ Card Content ━━
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(trip.destination.isEmpty ? trip.name : trip.destination)
                            .font(VoyagerFont.headlineMedium)
                            .foregroundStyle(Color.voyagerOnSurface)
                        Text(trip.dateRangeText)
                            .font(VoyagerFont.bodySmall)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                    
                    Spacer()
                    
                    // Countdown badge
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(TripCountdown.text(from: trip.startDate))
                            .font(VoyagerFont.labelCaps)
                            .tracking(0.4)
                            .foregroundStyle(TripCountdown.color(from: trip.startDate))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(TripCountdown.color(from: trip.startDate).opacity(0.12))
                            .clipShape(Capsule())
                        
                        // Status badge
                        Text(trip.status.rawValue.uppercased())
                            .font(.system(size: 10, weight: .medium))
                            .tracking(0.4)
                            .foregroundStyle(statusColor(trip.status).opacity(0.8))
                    }
                }
                
                // Divider
                Rectangle()
                    .fill(Color.voyagerOutlineVariant.opacity(0.15))
                    .frame(height: 0.5)
                
                // Summary row
                HStack(spacing: 8) {
                    if !trip.flights.isEmpty {
                        summaryPill(icon: "airplane", label: "\(trip.flights.count)")
                    }
                    if !trip.hotels.isEmpty {
                        summaryPill(icon: "bed.double", label: "\(trip.hotels.count)")
                    }
                    if !trip.carRentals.isEmpty {
                        summaryPill(icon: "car", label: "\(trip.carRentals.count)")
                    }
                    if !trip.dining.isEmpty {
                        summaryPill(icon: "fork.knife", label: "\(trip.dining.count)")
                    }
                    if !trip.activities.isEmpty {
                        summaryPill(icon: "figure.hiking", label: "\(trip.activities.count)")
                    }
                    
                    Spacer()
                    
                    // Packing progress ring (if items exist)
                    if totalPackingItems > 0 {
                        PackingProgressRing(progress: packingProgress, size: 28, lineWidth: 2.5)
                    }
                    
                    HStack(spacing: 4) {
                        Text("\(trip.durationDays)d")
                            .font(VoyagerFont.bodySmall)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.voyagerOutlineVariant)
                    }
                }
            }
            .padding(VoyagerSpacing.stackMedium)
        }
        .background(Color.voyagerSurfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerRadius.large)
                .stroke(Color.voyagerOutlineVariant.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: gradientColors[0].opacity(0.08), radius: 12, y: 4)
    }
    
    private func summaryPill(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(label)
                .font(VoyagerFont.labelCaps)
        }
        .foregroundStyle(Color.voyagerOnSurfaceVariant)
    }
    
    private func statusColor(_ status: TripStatus) -> Color {
        switch status {
        case .planning: return Color.voyagerPrimary
        case .live: return Color.voyagerPrimaryAccent
        case .completed: return Color.voyagerTertiary
        }
    }
}

// MARK: - Next Up Info

struct NextUpInfo {
    let trip: Trip
    let icon: String
    let title: String
    let subtitle: String
    let date: Date
    let accentColor: Color
}
