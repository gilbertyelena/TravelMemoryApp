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
            Destination.self,
            Memory.self,
            Photo.self,
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
            // Migration failed — delete old database and retry
            // This is safe during development; old sample data will be cleared
            print("⚠️ ModelContainer failed: \(error). Deleting old store and retrying...")
            
            let url = modelConfiguration.url
            let dir = url.deletingLastPathComponent()
            
            // Remove all SwiftData files
            if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for file in files where file.lastPathComponent.contains("default.store") {
                    try? FileManager.default.removeItem(at: file)
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
