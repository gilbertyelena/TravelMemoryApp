//
//  TravelMemoryApp.swift
//  TravelMemory
//
//  Created by Yelena Gilbert on 28/04/2026.
//

import SwiftUI
import SwiftData

/// iCloud sync switch. The models are CloudKit-compatible (defaults on
/// every attribute, optional relationships, no unique constraints).
/// To turn sync on:
///   1. In Xcode: TravelMemory target → Signing & Capabilities →
///      + iCloud → check CloudKit → add container
///      "iCloud.com.alenka.TravelSteward" (and Background Modes →
///      Remote notifications).
///   2. Flip `isEnabled` to true.
enum CloudSyncConfig {
    static let isEnabled = true
    static let containerID = "iCloud.com.alenka.TravelSteward"
}

@main
struct TravelMemoryApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Trip.self,
            FlightSegment.self,
            HotelBooking.self,
            CarRentalBooking.self,
            ParsedEmail.self,
            PackingCategoryModel.self,
            PackingItemModel.self,
            VaultDocument.self,
            DiningReservation.self,
            TripActivity.self,
        ])
        // Try CloudKit first when enabled; any failure (missing
        // entitlement, no iCloud account, simulator quirks) falls back
        // to the plain local store — never to the backup-and-reset path
        if CloudSyncConfig.isEnabled {
            let cloudConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(CloudSyncConfig.containerID)
            )
            if let container = try? ModelContainer(for: schema, configurations: [cloudConfiguration]) {
                return container
            }
            print("⚠️ CloudKit container unavailable — continuing with the local store")
        }

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Migration failed. Never delete user data — move the store
            // aside so it can be recovered, then start with a fresh one.
            print("⚠️ ModelContainer failed: \(error). Backing up store and starting fresh...")

            let url = modelConfiguration.url
            let dir = url.deletingLastPathComponent()
            let backupDir = dir.appendingPathComponent(
                "StoreBackup-\(Int(Date().timeIntervalSince1970))",
                isDirectory: true
            )

            if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
                // Moves default.store plus its -shm/-wal sidecar files
                for file in files where file.lastPathComponent.hasPrefix("default.store") {
                    try? FileManager.default.moveItem(
                        at: file,
                        to: backupDir.appendingPathComponent(file.lastPathComponent)
                    )
                }
            }

            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer after reset: \(error)")
            }
        }
    }()

    init() {
        // Check-in reminders open the airline's check-in page on tap
        NotificationRouter.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
