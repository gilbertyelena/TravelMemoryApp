//
//  OnboardingOverlay.swift
//  TravelMemory
//
//  First-launch welcome tips that appear once and can be dismissed.
//  Uses @AppStorage to track whether onboarding has been shown.
//

import SwiftUI

struct OnboardingOverlay: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var currentPage = 0
    @State private var appeared = false
    
    var showOverlay: Bool { !hasSeenOnboarding }
    
    let tips: [(icon: String, title: String, subtitle: String, color: String)] = [
        ("airplane.departure", "Plan Your Trips", "Create trips and add flights, hotels,\nand car rentals to your itinerary.", "#0A84FF"),
        ("envelope.open", "Import from Email", "Paste booking confirmation emails\nand we'll extract the details for you.", "#FFB868"),
        ("lock.shield.fill", "Secure Vault", "Store passport photos, visas, and\nboarding passes behind biometric lock.", "#667EEA"),
        ("suitcase.fill", "Packing Lists", "Never forget an item with smart\npacking checklists for every trip.", "#38EF7D"),
    ]
    
    var body: some View {
        if showOverlay {
            ZStack {
                // Backdrop
                Color.black.opacity(0.85)
                    .ignoresSafeArea()
                    .onTapGesture { /* block taps */ }
                
                VStack(spacing: 0) {
                    Spacer()
                    
                    // Card
                    VStack(spacing: 24) {
                        // Welcome title
                        if currentPage == 0 {
                            VStack(spacing: 8) {
                                Text("Welcome to")
                                    .font(VoyagerFont.bodyLargeFallback)
                                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                                Text("Travel Steward")
                                    .font(VoyagerFont.headlineLargeFallback)
                                    .foregroundStyle(Color.voyagerPrimary)
                            }
                            .padding(.bottom, 8)
                        }
                        
                        // Tip content
                        let tip = tips[currentPage]
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: tip.color).opacity(0.12))
                                    .frame(width: 72, height: 72)
                                Image(systemName: tip.icon)
                                    .font(.system(size: 30))
                                    .foregroundStyle(Color(hex: tip.color))
                                    .symbolEffect(.bounce, value: currentPage)
                            }
                            
                            Text(tip.title)
                                .font(VoyagerFont.headlineMediumFallback)
                                .foregroundStyle(Color.voyagerOnSurface)
                            
                            Text(tip.subtitle)
                                .font(VoyagerFont.bodySmallFallback)
                                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                        }
                        
                        // Page dots
                        HStack(spacing: 8) {
                            ForEach(0..<tips.count, id: \.self) { i in
                                Capsule()
                                    .fill(i == currentPage ? Color.voyagerPrimary : Color.voyagerSurfaceContainerHighest)
                                    .frame(width: i == currentPage ? 20 : 6, height: 6)
                                    .animation(.easeOut(duration: 0.25), value: currentPage)
                            }
                        }
                        
                        // Buttons
                        HStack(spacing: 12) {
                            if currentPage > 0 {
                                Button {
                                    withAnimation { currentPage -= 1 }
                                } label: {
                                    Text("BACK")
                                        .font(VoyagerFont.labelCapsFallback)
                                        .tracking(0.6)
                                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color.voyagerSurfaceContainerHigh)
                                        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                                }
                            }
                            
                            Button {
                                if currentPage < tips.count - 1 {
                                    withAnimation { currentPage += 1 }
                                } else {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        hasSeenOnboarding = true
                                    }
                                }
                            } label: {
                                Text(currentPage < tips.count - 1 ? "NEXT" : "GET STARTED")
                                    .font(VoyagerFont.labelCapsFallback)
                                    .tracking(0.6)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.voyagerPrimaryAccent)
                                    .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                            }
                        }
                        
                        // Skip
                        Button {
                            withAnimation(.easeOut(duration: 0.3)) {
                                hasSeenOnboarding = true
                            }
                        } label: {
                            Text("Skip")
                                .font(VoyagerFont.bodySmallFallback)
                                .foregroundStyle(Color.voyagerOnSurfaceVariant.opacity(0.6))
                        }
                    }
                    .padding(24)
                    .background(Color.voyagerSurfaceContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.voyagerOutlineVariant.opacity(0.2), lineWidth: 0.5)
                    )
                    .shadow(color: Color.voyagerPrimaryAccent.opacity(0.15), radius: 32, y: -8)
                    .padding(.horizontal, 24)
                    
                    Spacer()
                        .frame(height: 60)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 40)
            }
            .transition(.opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                    appeared = true
                }
            }
        }
    }
}
