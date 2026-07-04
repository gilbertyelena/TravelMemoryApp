//
//  VoyagerTabView.swift
//  TravelMemory
//
//  Main navigation container with the Voyager bottom tab bar.
//  Implements: Trips, Explore, Vault, Profile tabs
//

import SwiftUI

struct VoyagerTabView: View {
    @State private var selectedTab: VoyagerTab = .trips
    
    enum VoyagerTab: String, CaseIterable {
        case trips, explore, vault, profile
        
        var label: String {
            rawValue.capitalized
        }
        
        var icon: String {
            switch self {
            case .trips: return "airplane.departure"
            case .explore: return "safari"
            case .vault: return "lock.fill"
            case .profile: return "person.fill"
            }
        }
        
        var activeIcon: String {
            switch self {
            case .trips: return "airplane.departure"
            case .explore: return "safari.fill"
            case .vault: return "lock.fill"
            case .profile: return "person.fill"
            }
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Content
            Group {
                switch selectedTab {
                case .trips:
                    TripsListView()
                case .explore:
                    NavigationStack {
                        SpatialMemoryBridgeView()
                    }
                case .vault:
                    NavigationStack {
                        SecureVaultView()
                    }
                case .profile:
                    NavigationStack {
                        ProfilePlaceholderView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Custom Bottom Nav Bar
            voyagerBottomBar
        }
        .ignoresSafeArea(.keyboard)
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Bottom Navigation Bar
    
    private var voyagerBottomBar: some View {
        HStack {
            ForEach(VoyagerTab.allCases, id: \.self) { tab in
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: selectedTab == tab ? tab.activeIcon : tab.icon)
                        .font(.system(size: 22))
                        .symbolRenderingMode(.hierarchical)
                        .scaleEffect(selectedTab == tab ? 1.1 : 1.0)
                    
                    Text(tab.label)
                        .font(VoyagerFont.labelCapsFallback)
                        .tracking(0.6)
                        .textCase(.uppercase)
                }
                .foregroundStyle(
                    selectedTab == tab
                    ? Color.voyagerPrimary
                    : Color.voyagerOnSurfaceVariant.opacity(0.6)
                )
                .if(selectedTab == tab) { view in
                    view.voyagerGlow(color: .voyagerPrimary, radius: 12, opacity: 0.3)
                }
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .background(Color.voyagerBackground.opacity(0.9))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.voyagerOutlineVariant.opacity(0.2))
                        .frame(height: 0.5)
                }
                .shadow(color: Color.voyagerPrimaryAccent.opacity(0.15), radius: 12, y: -4)
        )
    }
}

// MARK: - Profile Placeholder

struct ProfilePlaceholderView: View {
    var body: some View {
        ZStack {
            Color.voyagerBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "person.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.voyagerPrimary)
                Text("Profile")
                    .font(VoyagerFont.headlineMediumFallback)
                    .foregroundStyle(Color.voyagerOnSurface)
                Text("Coming Soon")
                    .font(VoyagerFont.bodySmallFallback)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }
        }
    }
}

// MARK: - Voyager Top App Bar

struct VoyagerTopBar: View {
    var showNotificationBadge: Bool = false
    var notificationCount: Int = 0
    
    var body: some View {
        HStack {
            // Profile Avatar
            Circle()
                .fill(Color.voyagerSurfaceContainerHigh)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                )
                .overlay(
                    Circle()
                        .stroke(Color.voyagerOutlineVariant, lineWidth: 0.5)
                )
            
            Spacer()
            
            // Brand Name
            Text("Travel Steward")
                .font(VoyagerFont.headlineMediumFallback)
                .foregroundStyle(Color.voyagerPrimary)
                .tracking(-0.5)
            
            Spacer()
            
            // Notifications
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.voyagerPrimary)
                
                if showNotificationBadge {
                    VoyagerNotificationPill(
                        text: "\(notificationCount) New"
                    )
                    .scaleEffect(0.6)
                    .offset(x: 16, y: -8)
                }
            }
        }
        .padding(.horizontal, VoyagerSpacing.marginMain)
        .frame(height: 56)
        .background(
            Color.voyagerBackground.opacity(0.8)
                .background(.ultraThinMaterial)
        )
    }
}

struct VoyagerTabView_Previews: PreviewProvider {
    static var previews: some View {
        VoyagerTabView()
    }
}
