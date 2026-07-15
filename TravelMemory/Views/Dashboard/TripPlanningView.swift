//
//  TripPlanningView.swift
//  TravelMemory
//
//  The main trip dashboard. Shows real trips from SwiftData
//  with an empty state when no trips exist yet.
//

import SwiftUI
import SwiftData

struct TripPlanningView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.startDate, order: .forward) private var trips: [Trip]
    
    @State private var animateTimeline = false
    @State private var showLiveItinerary = false
    @State private var showInbox = false
    @State private var showPacking = false
    
    /// The currently selected / most relevant trip
    private var activeTrip: Trip? {
        // Prefer a "live" trip, then "planning", then most recent
        trips.first { $0.status == .live }
        ?? trips.first { $0.status == .planning }
        ?? trips.first
    }
    
    var body: some View {
        ZStack {
            Color.voyagerBackground.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Top Bar
                    let pendingCount = trips.reduce(0) { $0 + $1.pendingReviewCount }
                    VoyagerTopBar(showNotificationBadge: pendingCount > 0, notificationCount: pendingCount)
                    
                    if let trip = activeTrip {
                        // Trip Header
                        tripHeader(for: trip)
                            .padding(.top, VoyagerSpacing.stackLarge)
                        
                        // Quick Actions
                        quickActions(for: trip)
                            .padding(.top, VoyagerSpacing.stackLarge)
                        
                        // Timeline
                        timelineSection(for: trip)
                            .padding(.top, 32)
                    } else {
                        // Empty State
                        emptyState
                            .padding(.top, 60)
                    }
                }
                .padding(.bottom, 120)
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $showLiveItinerary) {
            LiveItineraryView()
        }
        .navigationDestination(isPresented: $showInbox) {
            InboxReviewView()
        }
        .navigationDestination(isPresented: $showPacking) {
            // Packing is now accessed via Trip Detail → Packing List
            EmptyView()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                animateTimeline = true
            }
        }
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
            }
            
            VStack(spacing: 8) {
                Text("No Trips Yet")
                    .font(VoyagerFont.headlineMedium)
                    .foregroundStyle(Color.voyagerOnSurface)
                
                Text("Forward a booking confirmation email\nto start building your itinerary")
                    .font(VoyagerFont.bodySmall)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            
            // Hint arrow pointing to the floating button
            VStack(spacing: 8) {
                Text("TAP THE ENVELOPE BUTTON BELOW")
                    .font(VoyagerFont.labelCaps)
                    .tracking(1.0)
                    .foregroundStyle(Color.voyagerPrimary.opacity(0.6))
                
                Image(systemName: "arrow.down")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.voyagerPrimary.opacity(0.4))
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, VoyagerSpacing.marginMain)
    }
    
    // MARK: - Quick Actions
    
    private func quickActions(for trip: Trip) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VoyagerSpacing.gutter) {
                quickActionCard(
                    icon: "airplane",
                    title: "Live Mode",
                    subtitle: trip.flights.isEmpty ? "No flights" : "\(trip.flights.count) flight\(trip.flights.count == 1 ? "" : "s")",
                    color: Color.voyagerPrimaryAccent
                ) { showLiveItinerary = true }
                
                let reviewCount = trip.pendingReviewCount
                quickActionCard(
                    icon: "exclamationmark.circle",
                    title: "Action Needed",
                    subtitle: reviewCount == 0 ? "All clear" : "\(reviewCount) to review",
                    color: reviewCount > 0 ? Color.voyagerTertiary : Color.voyagerOnSurfaceVariant
                ) { showInbox = true }
                
                quickActionCard(
                    icon: "suitcase",
                    title: "Packing",
                    subtitle: "Checklist",
                    color: Color.voyagerPrimary
                ) { showPacking = true }
            }
            .padding(.horizontal, VoyagerSpacing.marginMain)
        }
    }
    
    private func quickActionCard(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundStyle(color)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(VoyagerFont.bodySmallSemibold)
                        .foregroundStyle(Color.voyagerOnSurface)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
            .padding(12)
            .background(Color.voyagerSurfaceContainer)
            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: VoyagerRadius.large)
                    .stroke(Color.voyagerOutlineVariant.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Trip Header
    
    private func tripHeader(for trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: VoyagerSpacing.stackSmall) {
            Text(trip.destination.isEmpty ? trip.name : trip.destination)
                .font(VoyagerFont.headlineLarge)
                .foregroundStyle(Color.voyagerOnBackground)
            
            Text("\(trip.dateRangeText) • \(trip.durationDays) Day\(trip.durationDays == 1 ? "" : "s")")
                .font(VoyagerFont.bodyLarge)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            
            // Status
            HStack(spacing: VoyagerSpacing.gutter) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.voyagerSurfaceContainerHigh)
                            .frame(height: 4)
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(statusColor(for: trip))
                            .frame(width: geo.size.width * statusProgress(for: trip), height: 4)
                    }
                }
                .frame(height: 4)
                
                Text(trip.status.rawValue.uppercased())
                    .font(VoyagerFont.labelCaps)
                    .tracking(0.6)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }
            .padding(.top, VoyagerSpacing.stackMedium)
        }
        .padding(.horizontal, VoyagerSpacing.marginMain)
    }
    
    private func statusColor(for trip: Trip) -> Color {
        switch trip.status {
        case .planning: return Color.voyagerPrimary
        case .live: return Color.voyagerPrimaryAccent
        case .completed: return Color.voyagerTertiary
        }
    }
    
    private func statusProgress(for trip: Trip) -> CGFloat {
        switch trip.status {
        case .planning: return 0.15
        case .live: return 0.6
        case .completed: return 1.0
        }
    }
    
    // MARK: - Timeline Section
    
    private func timelineSection(for trip: Trip) -> some View {
        ZStack(alignment: .leading) {
            // Vertical Spine
            if !trip.flights.isEmpty || !trip.hotels.isEmpty || !trip.carRentals.isEmpty {
                Rectangle()
                    .fill(Color.voyagerTimelineSpine)
                    .frame(width: 2)
                    .padding(.leading, VoyagerSpacing.timelineOffset)
                    .padding(.top, 16)
            }
            
            VStack(spacing: VoyagerSpacing.stackLarge) {
                // Flight Cards
                ForEach(trip.flights, id: \.id) { flight in
                    flightCard(flight, isFirst: flight.id == trip.flights.first?.id)
                }
                
                // Hotel Cards
                ForEach(trip.hotels, id: \.id) { hotel in
                    hotelCard(hotel)
                        .padding(.top, VoyagerSpacing.stackSmall)
                }
                
                // Car Rental Cards
                ForEach(trip.carRentals, id: \.id) { car in
                    carRentalCard(car)
                        .padding(.top, VoyagerSpacing.stackSmall)
                }
                
                // If trip has no items yet
                if trip.flights.isEmpty && trip.hotels.isEmpty && trip.carRentals.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.dashed")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.voyagerOnSurfaceVariant.opacity(0.5))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No itinerary items yet")
                                .font(VoyagerFont.bodySmall)
                                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                            Text("Forward a confirmation email to add flights, hotels, and more")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.voyagerOnSurfaceVariant.opacity(0.6))
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.voyagerSurfaceContainerLow.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
                    .overlay(
                        RoundedRectangle(cornerRadius: VoyagerRadius.large)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                            .foregroundStyle(Color.voyagerOutlineVariant.opacity(0.3))
                    )
                }
            }
        }
        .padding(.horizontal, VoyagerSpacing.marginMain)
    }
    
    // MARK: - Flight Card
    
    private func flightCard(_ flight: FlightSegment, isFirst: Bool) -> some View {
        let timeFmt = DateFormatter()
        let _ = timeFmt.dateFormat = "HH:mm"
        
        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 4) {
                VoyagerTimelineNode(isActive: isFirst)
                Text(timeFmt.string(from: flight.departureTime))
                    .font(VoyagerFont.labelCaps)
                    .tracking(0.5)
                    .foregroundStyle(isFirst ? Color.voyagerPrimary : Color.voyagerOnSurfaceVariant)
            }
            .frame(width: 64)
            
            VStack(spacing: VoyagerSpacing.stackMedium) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "airplane.departure")
                            .foregroundStyle(Color.voyagerPrimary)
                        Text(flight.airlineAndFlight.uppercased())
                            .font(VoyagerFont.labelCaps)
                            .tracking(0.6)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                    Spacer()
                    if !flight.gate.isEmpty {
                        Text("GATE \(flight.gate)")
                            .font(VoyagerFont.labelCaps)
                            .tracking(0.4)
                            .foregroundStyle(Color.voyagerOnSurface)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.voyagerSurfaceVariant)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(flight.departureAirport)
                            .font(VoyagerFont.headlineMedium)
                            .foregroundStyle(Color.voyagerOnBackground)
                        Text(flight.departureCity)
                            .font(VoyagerFont.bodySmall)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                    
                    Spacer()
                    
                    ZStack {
                        Rectangle()
                            .fill(Color.voyagerOutlineVariant.opacity(0.5))
                            .frame(height: 1)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                            .padding(.horizontal, 4)
                            .background(Color.voyagerSurfaceContainerHigh)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(flight.arrivalAirport)
                            .font(VoyagerFont.headlineMedium)
                            .foregroundStyle(Color.voyagerOnBackground)
                        Text(flight.arrivalCity)
                            .font(VoyagerFont.bodySmall)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                }
            }
            .padding(VoyagerSpacing.stackMedium)
            .background(isFirst ? Color.voyagerSurfaceContainerHigh : Color.voyagerSurfaceContainerLow)
            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: VoyagerRadius.large)
                    .stroke(Color.voyagerOutlineVariant.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(isFirst ? 0.4 : 0.2), radius: 12, y: 4)
        }
    }
    
    // MARK: - Hotel Card
    
    private func hotelCard(_ hotel: HotelBooking) -> some View {
        let timeFmt = DateFormatter()
        let _ = timeFmt.dateFormat = "HH:mm"
        
        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 4) {
                VoyagerTimelineNode(isActive: false, size: 10)
                Text(timeFmt.string(from: hotel.checkInDate))
                    .font(VoyagerFont.labelCaps)
                    .tracking(0.5)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }
            .frame(width: 64)
            
            HStack(spacing: VoyagerSpacing.stackMedium) {
                RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                    .fill(
                        LinearGradient(
                            colors: [Color.voyagerSurfaceVariant, Color.voyagerSurfaceContainerHighest],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "building.2")
                            .foregroundStyle(Color.voyagerOnSurfaceVariant.opacity(0.5))
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "bed.double")
                            .font(.system(size: 12))
                        Text("CHECK-IN • \(hotel.nightsCount) NIGHT\(hotel.nightsCount == 1 ? "" : "S")")
                            .tracking(0.6)
                    }
                    .font(VoyagerFont.labelCaps)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    
                    Text(hotel.hotelName)
                        .font(VoyagerFont.bodyLarge.bold())
                        .foregroundStyle(Color.voyagerOnBackground)
                        .lineLimit(2)
                    
                    if !hotel.address.isEmpty {
                        Text(hotel.address)
                            .font(VoyagerFont.bodySmall)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                }
            }
            .padding(VoyagerSpacing.stackMedium)
            .background(Color.voyagerSurfaceContainerLow)
            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
        }
    }
    
    // MARK: - Car Rental Card
    
    private func carRentalCard(_ car: CarRentalBooking) -> some View {
        let timeFmt = DateFormatter()
        let _ = timeFmt.dateFormat = "HH:mm"
        
        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 4) {
                VoyagerTimelineNode(isActive: false, size: 10)
                Text(timeFmt.string(from: car.pickupTime))
                    .font(VoyagerFont.labelCaps)
                    .tracking(0.5)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }
            .frame(width: 64)
            
            VStack(alignment: .leading, spacing: VoyagerSpacing.stackSmall) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "car")
                                .font(.system(size: 12))
                            Text("PICKUP")
                                .tracking(0.6)
                        }
                        .font(VoyagerFont.labelCaps)
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                        
                        Text(car.company)
                            .font(VoyagerFont.bodyLarge.bold())
                            .foregroundStyle(Color.voyagerOnBackground)
                    }
                    Spacer()
                    if car.isPrepaid {
                        Text("PRE-PAID")
                            .font(VoyagerFont.labelCaps)
                            .tracking(0.4)
                            .foregroundStyle(Color.voyagerTertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.voyagerTertiary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                
                Text("\(car.vehicleType)\(!car.confirmationCode.isEmpty ? " • #\(car.confirmationCode)" : "")")
                    .font(VoyagerFont.bodySmall)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }
            .padding(VoyagerSpacing.stackMedium)
            .background(Color.voyagerSurfaceContainerLow)
            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
        }
    }
}

struct TripPlanningView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TripPlanningView()
        }
        .modelContainer(for: [Trip.self, FlightSegment.self, HotelBooking.self, CarRentalBooking.self, ParsedEmail.self], inMemory: true)
        .preferredColorScheme(.dark)
    }
}
