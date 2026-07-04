//
//  TravelMemoryApp.swift
//  TravelMemory
//
//  Created by Yelena Gilbert on 28/04/2026.
//

import SwiftUI
import SwiftData

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
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

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

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
