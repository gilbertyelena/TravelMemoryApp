//
//  ContentView.swift
//  TravelMemory
//
//  Created by Yelena Gilbert on 28/04/2026.
//

import SwiftUI
import SwiftData

// MARK: - Main Content View

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPendingEmailSheet = false
    @State private var pendingEmail: SharedDataStore.SharedEmail?
    @State private var showClipboardBanner = false
    @State private var clipboardText = ""
    @State private var showClipboardParse = false
    
    /// Keywords that suggest clipboard content is a booking email
    private let bookingKeywords = [
        "confirmation", "booking", "reservation", "itinerary",
        "flight", "departure", "arrival", "check-in", "check-out",
        "boarding pass", "passenger", "hotel", "accommodation",
        "car rental", "pickup", "lufthansa", "ryanair", "easyjet",
        "british airways", "booking.com", "airbnb", "expedia"
    ]
    
    var body: some View {
        ZStack {
            VoyagerTabView()
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        checkForPendingEmails()
                    }
                }
                .onAppear {
                    checkForPendingEmails()
                }
                .sheet(isPresented: $showPendingEmailSheet) {
                    if let email = pendingEmail {
                        PendingEmailProcessView(email: email) {
                            // After processing, remove from queue and check for more
                            SharedDataStore.removePendingEmail(id: email.id)
                            pendingEmail = nil
                            showPendingEmailSheet = false
                            // Check for more pending emails
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                checkForPendingEmails()
                            }
                        }
                    }
                }
                .sheet(isPresented: $showClipboardParse) {
                    ClipboardEmailView(emailBody: clipboardText)
                }
            
            // First-launch onboarding overlay
            OnboardingOverlay()
            
            // Clipboard detection banner
            if showClipboardBanner {
                VStack {
                    clipboardBanner
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showClipboardBanner)
            }
        }
    }
    
    // MARK: - Clipboard Banner
    
    private var clipboardBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.voyagerPrimaryAccent.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.voyagerPrimaryAccent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Booking detected")
                    .font(VoyagerFont.bodySmallFallback)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.voyagerOnSurface)
                Text("Looks like a travel confirmation on your clipboard")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }
            
            Spacer()
            
            Button {
                withAnimation { showClipboardBanner = false }
                showClipboardParse = true
            } label: {
                Text("IMPORT")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.voyagerPrimaryAccent)
                    .clipShape(Capsule())
            }
            
            Button {
                withAnimation { showClipboardBanner = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    .padding(6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: VoyagerRadius.large)
                .fill(Color.voyagerSurfaceContainerHigh)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerRadius.large)
                .stroke(Color.voyagerPrimaryAccent.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Clipboard Detection
    
    private func checkClipboard() {
        guard !showClipboardParse, !showPendingEmailSheet else { return }
        
        // Only check if clipboard has text
        guard UIPasteboard.general.hasStrings,
              let text = UIPasteboard.general.string,
              text.count > 50 else { return }
        
        let lowered = text.lowercased()
        let matchCount = bookingKeywords.filter { lowered.contains($0) }.count
        
        // Need at least 2 keyword matches to suggest it's a booking
        if matchCount >= 2 {
            clipboardText = text
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.5)) {
                showClipboardBanner = true
            }
            
            // Auto-dismiss after 8 seconds if not acted on
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                withAnimation { showClipboardBanner = false }
            }
        }
    }
    
    private func checkForPendingEmails() {
        let pending = SharedDataStore.loadPendingEmails()
        if let first = pending.first {
            pendingEmail = first
            showPendingEmailSheet = true
        }
    }
}

// MARK: - Clipboard Email View (streamlined parser)

struct ClipboardEmailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let emailBody: String
    @State private var isProcessing = false
    @State private var parseResult: EmailParser.ParseResult?
    @State private var createdTrip: Trip?
    @State private var showResult = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.voyagerBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: VoyagerSpacing.stackLarge) {
                        // Header
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.voyagerPrimaryAccent.opacity(0.12))
                                    .frame(width: 72, height: 72)
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 30))
                                    .foregroundStyle(Color.voyagerPrimaryAccent)
                            }
                            
                            Text("Import from Clipboard")
                                .font(VoyagerFont.headlineMediumFallback)
                                .foregroundStyle(Color.voyagerOnSurface)
                            
                            Text("We found what looks like a booking\nconfirmation on your clipboard")
                                .font(VoyagerFont.bodySmallFallback)
                                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                        }
                        .padding(.top, 8)
                        
                        // Preview of clipboard content
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CLIPBOARD CONTENT")
                                .font(VoyagerFont.labelCapsFallback)
                                .tracking(1.0)
                                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                            
                            Text(emailBody.prefix(300) + (emailBody.count > 300 ? "..." : ""))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.voyagerInputBackground)
                                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                                .overlay(
                                    RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                                        .stroke(Color.voyagerInputBorder, lineWidth: 1)
                                )
                        }
                        
                        // Parse button
                        Button { parseClipboard() } label: {
                            HStack(spacing: 8) {
                                if isProcessing {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "wand.and.stars")
                                }
                                Text(isProcessing ? "PARSING..." : "EXTRACT BOOKING DETAILS")
                            }
                        }
                        .buttonStyle(VoyagerPrimaryButtonStyle())
                        .disabled(isProcessing)
                        
                        // How-to tip
                        HStack(spacing: 10) {
                            Image(systemName: "lightbulb")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.voyagerTertiary)
                            Text("**Tip:** In Apple Mail, open a booking email → tap the body → Select All → Copy, then come back here.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                        }
                        .padding(12)
                        .background(Color.voyagerTertiary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                    }
                    .padding(.horizontal, VoyagerSpacing.marginMain)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Clipboard Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
            .sheet(isPresented: $showResult) {
                if let result = parseResult {
                    ParseResultView(
                        result: result,
                        trip: createdTrip,
                        onAccept: { dismiss() },
                        onDiscard: {
                            if let trip = createdTrip {
                                modelContext.delete(trip)
                                try? modelContext.save()
                            }
                            showResult = false
                        }
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func parseClipboard() {
        isProcessing = true
        Task {
            let service = EmailIngestionService(modelContext: modelContext)
            let trip = await service.ingestEmail(subject: "Clipboard Import", body: emailBody, sender: "")
            self.parseResult = service.lastParseResult
            self.createdTrip = trip
            self.isProcessing = false
            self.showResult = true
        }
    }
}

// MARK: - Legacy Tab View (TravelMemory)

struct LegacyTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            DestinationListView()
                .tabItem {
                    Label("Trips", systemImage: "suitcase.fill")
                }
                .tag(0)
            
            MapTabView()
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .tag(1)
        }
        .tint(.orange)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .modelContainer(for: [Destination.self, Memory.self, Photo.self], inMemory: true)
    }
}
