//
//  LiveItineraryView.swift
//  TravelMemory
//
//  Live mode view — shows upcoming flight info from real data.
//  Empty state when no flights are scheduled.
//

import SwiftUI
import SwiftData

struct LiveItineraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FlightSegment.departureTime, order: .forward) private var flights: [FlightSegment]
    
    @State private var countdownTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var now = Date()
    
    /// Next upcoming flight
    private var nextFlight: FlightSegment? {
        flights.first { $0.departureTime > Date() } ?? flights.first
    }
    
    var body: some View {
        ZStack {
            Color.voyagerBackground.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: VoyagerSpacing.stackLarge) {
                    // Back button
                    header
                    
                    if let flight = nextFlight {
                        liveFlightBoard(flight)
                            .padding(.horizontal, VoyagerSpacing.marginMain)
                        
                        quickActionsGrid
                            .padding(.horizontal, VoyagerSpacing.marginMain)
                    } else {
                        emptyState
                    }
                }
                .padding(.bottom, 120)
            }
        }
        .navigationBarHidden(true)
        .onReceive(countdownTimer) { _ in
            now = Date()
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                    Text("Back")
                        .font(VoyagerFont.bodySmall)
                }
                .foregroundStyle(Color.voyagerPrimary)
            }
            Spacer()
            Text("LIVE MODE")
                .font(VoyagerFont.labelCaps)
                .tracking(1.2)
                .foregroundStyle(Color.voyagerPrimaryAccent)
        }
        .padding(.horizontal, VoyagerSpacing.marginMain)
        .padding(.top, 8)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.voyagerPrimary.opacity(0.06))
                    .frame(width: 120, height: 120)
                Image(systemName: "airplane")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(Color.voyagerPrimary.opacity(0.6))
            }
            
            VStack(spacing: 6) {
                Text("No Upcoming Flights")
                    .font(VoyagerFont.headlineMedium)
                    .foregroundStyle(Color.voyagerOnSurface)
                Text("Forward a flight confirmation email\nto see live boarding info here")
                    .font(VoyagerFont.bodySmall)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    // MARK: - Live Flight Board
    
    private func liveFlightBoard(_ flight: FlightSegment) -> some View {
        let timeUntilDeparture = max(0, Int(flight.departureTime.timeIntervalSince(now)))
        let hours = timeUntilDeparture / 3600
        let minutes = (timeUntilDeparture % 3600) / 60
        let seconds = timeUntilDeparture % 60
        let countdown = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        
        return VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                if !flight.gate.isEmpty {
                    VoyagerNotificationPill(text: "GATE \(flight.gate)")
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(flight.airlineAndFlight)
                        .font(VoyagerFont.bodySmall)
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    Text(timeUntilDeparture > 0 ? "UPCOMING" : "DEPARTED")
                        .font(VoyagerFont.labelCaps)
                        .tracking(0.6)
                        .foregroundStyle(timeUntilDeparture > 0 ? Color.voyagerPrimary : Color.voyagerOnSurfaceVariant)
                }
            }
            .padding(.bottom, 24)
            
            // Countdown
            if timeUntilDeparture > 0 {
                VStack(spacing: 4) {
                    Text("BOARDING IN")
                        .font(VoyagerFont.labelCaps)
                        .tracking(1.5)
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    
                    Text(countdown)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: Color.voyagerPrimaryContainer.opacity(0.6), radius: 16)
                        .shadow(color: Color.voyagerPrimaryAccent.opacity(0.4), radius: 32)
                }
                .padding(.vertical, 16)
            }
            
            // Route
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(flight.departureAirport)
                        .font(VoyagerFont.headlineMedium)
                        .foregroundStyle(Color.voyagerOnSurface)
                    Text(flight.departureCity)
                        .font(VoyagerFont.bodySmall)
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
                
                Spacer()
                
                ZStack {
                    Rectangle()
                        .fill(Color.voyagerOutlineVariant.opacity(0.3))
                        .frame(height: 1)
                    Image(systemName: "airplane")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.voyagerPrimary)
                        .padding(.horizontal, 8)
                        .background(Color.voyagerSurfaceContainerHigh)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(flight.arrivalAirport)
                        .font(VoyagerFont.headlineMedium)
                        .foregroundStyle(Color.voyagerOnSurface)
                    Text(flight.arrivalCity)
                        .font(VoyagerFont.bodySmall)
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
            .padding(.top, 24)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.voyagerOutlineVariant.opacity(0.2))
                    .frame(height: 0.5)
            }
            
            // Seat info
            if !flight.seat.isEmpty {
                HStack {
                    Text("SEAT \(flight.seat)")
                        .font(VoyagerFont.labelCaps)
                        .tracking(0.6)
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    Spacer()
                    if !flight.confirmationCode.isEmpty {
                        Text("REF: \(flight.confirmationCode)")
                            .font(VoyagerFont.labelCaps)
                            .tracking(0.6)
                            .foregroundStyle(Color.voyagerPrimary)
                    }
                }
                .padding(.top, 16)
            }
        }
        .padding(VoyagerSpacing.stackMedium)
        .background(Color.voyagerSurfaceContainerHigh)
        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerRadius.large)
                .stroke(Color.voyagerOutlineVariant.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    }
    
    // MARK: - Quick Actions Grid
    
    private var quickActionsGrid: some View {
        HStack(spacing: VoyagerSpacing.gutter) {
            quickActionButton(icon: "qrcode.viewfinder", label: "Boarding Pass")
            quickActionButton(icon: "car.fill", label: "Order Ride")
        }
    }
    
    private func quickActionButton(icon: String, label: String) -> some View {
        Button(action: {}) {
            VStack(spacing: 12) {
                Circle()
                    .fill(Color.voyagerPrimary.opacity(0.1))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 20))
                            .foregroundStyle(Color.voyagerPrimary)
                    )
                Text(label)
                    .font(VoyagerFont.bodySmallMedium)
                    .foregroundStyle(Color.voyagerOnSurface)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, VoyagerSpacing.stackMedium)
            .background(Color.voyagerSurfaceContainer)
            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: VoyagerRadius.large)
                    .stroke(Color.voyagerOutlineVariant.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct LiveItineraryView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            LiveItineraryView()
        }
        .modelContainer(for: [FlightSegment.self], inMemory: true)
        .preferredColorScheme(.dark)
    }
}
