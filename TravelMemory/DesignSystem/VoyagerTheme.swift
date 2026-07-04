//
//  VoyagerTheme.swift
//  TravelMemory
//
//  Voyager Design System
//  Based on Project Voyager DESIGN.md specification
//

import SwiftUI

// MARK: - Color Tokens

extension Color {
    // Surface System
    static let voyagerBackground = Color(hex: "#000000")
    static let voyagerSurface = Color(hex: "#121317")
    static let voyagerSurfaceDim = Color(hex: "#121317")
    static let voyagerSurfaceBright = Color(hex: "#38393D")
    static let voyagerSurfaceContainerLowest = Color(hex: "#0D0E12")
    static let voyagerSurfaceContainerLow = Color(hex: "#1A1B1F")
    static let voyagerSurfaceContainer = Color(hex: "#1E1F23")
    static let voyagerSurfaceContainerHigh = Color(hex: "#292A2E")
    static let voyagerSurfaceContainerHighest = Color(hex: "#343539")
    static let voyagerSurfaceVariant = Color(hex: "#343539")
    
    // Cards — per design system Level 1
    static let voyagerCard = Color(hex: "#1C1C1E")
    // Elevated cards — Level 2
    static let voyagerCardElevated = Color(hex: "#2C2C2E")
    
    // On-Surface Text
    static let voyagerOnSurface = Color(hex: "#E3E2E7")
    static let voyagerOnSurfaceVariant = Color(hex: "#C0C6D6")
    static let voyagerOnBackground = Color(hex: "#E3E2E7")
    
    // Primary
    static let voyagerPrimary = Color(hex: "#AAC7FF")
    static let voyagerOnPrimary = Color(hex: "#003064")
    static let voyagerPrimaryContainer = Color(hex: "#3E90FF")
    static let voyagerOnPrimaryContainer = Color(hex: "#002957")
    static let voyagerPrimaryAccent = Color(hex: "#0A84FF")
    
    // Secondary
    static let voyagerSecondary = Color(hex: "#C8C6C8")
    static let voyagerOnSecondary = Color(hex: "#303032")
    static let voyagerSecondaryContainer = Color(hex: "#474649")
    
    // Tertiary (Alert/Orange)
    static let voyagerTertiary = Color(hex: "#FFB868")
    static let voyagerOnTertiary = Color(hex: "#482900")
    static let voyagerTertiaryContainer = Color(hex: "#CE7F00")
    
    // Error
    static let voyagerError = Color(hex: "#FFB4AB")
    static let voyagerOnError = Color(hex: "#690005")
    static let voyagerErrorContainer = Color(hex: "#93000A")
    static let voyagerOnErrorContainer = Color(hex: "#FFDAD6")
    
    // Outline
    static let voyagerOutline = Color(hex: "#8B91A0")
    static let voyagerOutlineVariant = Color(hex: "#414754")
    
    // Timeline spine
    static let voyagerTimelineSpine = Color(hex: "#3A3A3C")
    static let voyagerTimelineInactive = Color(hex: "#8E8E93")
    
    // Input fields
    static let voyagerInputBackground = Color(hex: "#121214")
    static let voyagerInputBorder = Color(hex: "#3A3A3C")
}

// MARK: - Hex Color Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct VoyagerFont {
    // Primary custom fonts — these require the .ttf files to be
    // added to the Xcode project and listed in Info.plist UIAppFonts
    
    /// Plus Jakarta Sans 34px Bold — page titles
    static let headlineLarge: Font = .custom("PlusJakartaSans-Bold", size: 34, relativeTo: .largeTitle)
    
    /// Plus Jakarta Sans 22px Bold — section headers
    static let headlineMedium: Font = .custom("PlusJakartaSans-Bold", size: 22, relativeTo: .title2)
    
    /// Inter 17px Regular — body text
    static let bodyLarge: Font = .custom("Inter-Regular", size: 17, relativeTo: .body)
    
    /// Inter 15px Regular — secondary body
    static let bodySmall: Font = .custom("Inter-Regular", size: 15, relativeTo: .subheadline)
    
    /// Inter 12px Semibold — labels, captions
    static let labelCaps: Font = .custom("Inter-SemiBold", size: 12, relativeTo: .caption)
    
    /// Inter 15px Medium — medium weight body
    static let bodyMedium: Font = .custom("Inter-Medium", size: 15, relativeTo: .subheadline)
}

// MARK: - Spacing Tokens

struct VoyagerSpacing {
    static let marginMain: CGFloat = 20
    static let gutter: CGFloat = 12
    static let stackSmall: CGFloat = 8
    static let stackMedium: CGFloat = 16
    static let stackLarge: CGFloat = 24
    static let timelineOffset: CGFloat = 32
    static let minTouchTarget: CGFloat = 44
}

// MARK: - Corner Radius Tokens

struct VoyagerRadius {
    static let small: CGFloat = 4
    static let medium: CGFloat = 8
    static let large: CGFloat = 12
    static let extraLarge: CGFloat = 16
    static let card: CGFloat = 16
    static let button: CGFloat = 12
    static let pill: CGFloat = 9999
}

// MARK: - Neon Glow Effect

struct VoyagerGlow: ViewModifier {
    var color: Color = .voyagerPrimaryAccent
    var radius: CGFloat = 12
    var opacity: Double = 0.4
    
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(opacity), radius: radius, x: 0, y: 0)
    }
}

extension View {
    func voyagerGlow(
        color: Color = .voyagerPrimaryAccent,
        radius: CGFloat = 12,
        opacity: Double = 0.4
    ) -> some View {
        modifier(VoyagerGlow(color: color, radius: radius, opacity: opacity))
    }
}

// MARK: - Card Style

struct VoyagerCardStyle: ViewModifier {
    var elevated: Bool = false
    
    func body(content: Content) -> some View {
        content
            .background(elevated ? Color.voyagerCardElevated : Color.voyagerCard)
            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: VoyagerRadius.card)
                    .stroke(Color.voyagerOutlineVariant.opacity(0.3), lineWidth: elevated ? 1 : 0)
            )
    }
}

extension View {
    func voyagerCard(elevated: Bool = false) -> some View {
        modifier(VoyagerCardStyle(elevated: elevated))
    }
}

// MARK: - Primary Button Style

struct VoyagerPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VoyagerFont.labelCaps)
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.voyagerPrimaryAccent)
            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.button))
            .voyagerGlow()
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Notification Pill

struct VoyagerNotificationPill: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(VoyagerFont.labelCaps)
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.voyagerTertiary)
            .clipShape(Capsule())
    }
}

// MARK: - Timeline Node

struct VoyagerTimelineNode: View {
    var isActive: Bool = false
    var size: CGFloat = 12
    
    var body: some View {
        Circle()
            .fill(isActive ? Color.voyagerPrimaryAccent : Color.voyagerSurfaceVariant)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(Color.voyagerBackground, lineWidth: 4)
            )
            .if(isActive) { view in
                view.voyagerGlow(radius: 8)
            }
    }
}

// MARK: - Conditional Modifier

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Offline Badge

struct VoyagerOfflineBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.icloud")
                .font(.system(size: 10))
            Text("OFFLINE AVAILABLE")
                .font(VoyagerFont.labelCaps)
                .tracking(0.8)
        }
        .foregroundStyle(Color.voyagerPrimaryAccent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.voyagerBackground.opacity(0.9))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.voyagerPrimaryAccent.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Destination Gradient

struct DestinationGradient {
    /// Returns a pair of gradient colors based on the destination name
    static func colors(for destination: String) -> [Color] {
        let lowered = destination.lowercased()
        
        // Tropical / Beach
        if ["beach", "island", "bali", "maldives", "hawaii", "cancun", "ibiza", "coast", "caribbean", "fiji"]
            .contains(where: { lowered.contains($0) }) {
            return [Color(hex: "#FF6B35"), Color(hex: "#F7C59F")]
        }
        // Major cities / Urban
        if ["tokyo", "new york", "london", "dubai", "singapore", "hong kong", "shanghai", "seoul"]
            .contains(where: { lowered.contains($0) }) {
            return [Color(hex: "#667EEA"), Color(hex: "#764BA2")]
        }
        // European charm
        if ["paris", "rome", "florence", "venice", "barcelona", "lisbon", "athens", "istanbul", "prague", "vienna"]
            .contains(where: { lowered.contains($0) }) {
            return [Color(hex: "#F093FB"), Color(hex: "#F5576C")]
        }
        // Nature / Mountains
        if ["mountain", "alps", "hiking", "switzerland", "nepal", "colorado", "patagonia", "iceland"]
            .contains(where: { lowered.contains($0) }) {
            return [Color(hex: "#11998E"), Color(hex: "#38EF7D")]
        }
        // Germany / Central Europe
        if ["munich", "berlin", "germany", "austria", "zurich"]
            .contains(where: { lowered.contains($0) }) {
            return [Color(hex: "#4FACFE"), Color(hex: "#00F2FE")]
        }
        
        // Default — pick from a set based on a stable hash of the name.
        // Swift's String.hash is seeded per process, so it would change
        // the gradient on every app launch; sum scalars instead.
        let gradients: [[Color]] = [
            [Color(hex: "#4FACFE"), Color(hex: "#00F2FE")],
            [Color(hex: "#43E97B"), Color(hex: "#38F9D7")],
            [Color(hex: "#FA709A"), Color(hex: "#FEE140")],
            [Color(hex: "#A18CD1"), Color(hex: "#FBC2EB")],
            [Color(hex: "#667EEA"), Color(hex: "#764BA2")],
            [Color(hex: "#FF9A9E"), Color(hex: "#FECFEF")],
        ]
        let stableHash = destination.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFFFFFF }
        return gradients[stableHash % gradients.count]
    }
}

// MARK: - Packing Progress Ring

struct PackingProgressRing: View {
    let progress: Double
    var size: CGFloat = 32
    var lineWidth: CGFloat = 3
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.voyagerSurfaceContainerHighest, lineWidth: lineWidth)
            
            Circle()
                .trim(from: 0, to: CGFloat(min(progress, 1.0)))
                .stroke(
                    progress >= 1.0 ? Color.voyagerPrimaryAccent : Color.voyagerPrimary,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: progress)
            
            if progress >= 1.0 {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.3, weight: .bold))
                    .foregroundStyle(Color.voyagerPrimaryAccent)
            } else {
                Text("\(Int(progress * 100))")
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Countdown Helper

struct TripCountdown {
    /// Returns a human-readable countdown string relative to a date
    static func text(from date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        
        if days > 1 {
            return "In \(days) days"
        } else if days == 1 {
            return "Tomorrow"
        } else if days == 0 {
            return "Today"
        } else if days == -1 {
            return "Yesterday"
        } else {
            return "\(abs(days)) days ago"
        }
    }
    
    /// Color for the countdown badge
    static func color(from date: Date) -> Color {
        let now = Date()
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        
        if days > 7 {
            return Color.voyagerPrimary
        } else if days > 0 {
            return Color.voyagerTertiary
        } else if days == 0 {
            return Color.voyagerPrimaryAccent
        } else {
            return Color.voyagerOnSurfaceVariant
        }
    }
}

// MARK: - Staggered Animation Modifier

struct StaggeredAppear: ViewModifier {
    let index: Int
    let appeared: Bool
    
    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(
                .easeOut(duration: 0.4).delay(Double(index) * 0.08),
                value: appeared
            )
    }
}

extension View {
    func staggeredAppear(index: Int, appeared: Bool) -> some View {
        modifier(StaggeredAppear(index: index, appeared: appeared))
    }
}

// MARK: - Shimmer Effect

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.1),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .offset(x: phase * geo.size.width)
                    .onAppear {
                        withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                            phase = 1
                        }
                    }
                }
            )
            .clipped()
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}
