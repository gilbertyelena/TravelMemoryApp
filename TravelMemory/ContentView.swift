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
    @State private var pendingEmail: SharedDataStore.SharedEmail?
    @State private var incomingTripFile: IncomingTripFile?

    /// Identifiable wrapper so .sheet(item:) can't present empty
    struct IncomingTripFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        ZStack {
            VoyagerTabView()
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        checkForPendingEmails()
                    }
                    // Keep the widget's "next up" snapshot fresh
                    WidgetSnapshotService.refresh(context: modelContext)
                    // Catch-all for changes made since the last sync
                    // (deletes, imports) — no-op unless enabled
                    CalendarSyncService.requestResync(context: modelContext)
                }
                .onAppear {
                    checkForPendingEmails()
                }
                .onOpenURL { url in
                    if url.pathExtension.lowercased() == "travelsteward" {
                        incomingTripFile = IncomingTripFile(url: url)
                    }
                }
                .sheet(item: $incomingTripFile) { file in
                    TripShareReceiveView(fileURL: file.url)
                }
                .sheet(item: $pendingEmail) { email in
                    PendingEmailProcessView(email: email) {
                        // After processing, remove from queue and check for more
                        SharedDataStore.removePendingEmail(id: email.id)
                        pendingEmail = nil
                        // Check for more pending emails
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            checkForPendingEmails()
                        }
                    }
                }

            // First-launch onboarding overlay
            OnboardingOverlay()
        }
    }

    private func checkForPendingEmails() {
        guard pendingEmail == nil else { return }
        pendingEmail = SharedDataStore.loadPendingEmails().first
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .modelContainer(for: [Trip.self], inMemory: true)
    }
}
