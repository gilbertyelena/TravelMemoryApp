//
//  WidgetSnapshotService.swift
//  TravelMemory
//
//  Keeps the app-group "next up" snapshot fresh so the widget always
//  shows the soonest upcoming itinerary item.
//

import Foundation
import SwiftData
import WidgetKit

@MainActor
struct WidgetSnapshotService {
    static func refresh(context: ModelContext) {
        let descriptor = FetchDescriptor<Trip>()
        guard let trips = try? context.fetch(descriptor) else { return }

        let now = Date()
        let upcoming = trips
            .flatMap(\.timelineItems)
            .filter { $0.eventDate > now && $0.status != .idea }
            .min { $0.eventDate < $1.eventDate }

        if let next = upcoming {
            SharedDataStore.saveNextUp(SharedDataStore.NextUpSnapshot(
                title: next.agendaTitle,
                detail: next.itemType.label.capitalized,
                date: next.eventDate,
                iconSystemName: next.itemType.icon
            ))
        } else {
            SharedDataStore.saveNextUp(nil)
        }

        WidgetCenter.shared.reloadAllTimelines()
    }
}
