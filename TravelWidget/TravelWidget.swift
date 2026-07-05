//
//  TravelWidget.swift
//  TravelWidget
//
//  "Next up" widget: the next flight, reservation, or activity, read
//  from the app-group snapshot the main app maintains. Supports the
//  home screen (small) and the lock screen (rectangular).
//

import WidgetKit
import SwiftUI

// MARK: - Timeline

struct NextUpEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedDataStore.NextUpSnapshot?
}

struct NextUpProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextUpEntry {
        NextUpEntry(
            date: .now,
            snapshot: SharedDataStore.NextUpSnapshot(
                title: "LH411 · JFK → MUC",
                detail: "Flight",
                date: .now.addingTimeInterval(2 * 3600),
                iconSystemName: "airplane.departure"
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NextUpEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextUpEntry>) -> Void) {
        let entry = currentEntry()
        // Refresh when the shown event passes, or hourly, whichever is sooner
        let eventDate = entry.snapshot?.date ?? .now.addingTimeInterval(3600)
        let refresh = max(min(eventDate, .now.addingTimeInterval(3600)), .now.addingTimeInterval(300))
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func currentEntry() -> NextUpEntry {
        NextUpEntry(date: .now, snapshot: SharedDataStore.loadNextUp())
    }
}

// MARK: - Views

struct NextUpWidgetView: View {
    var entry: NextUpEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, snapshot.date > .now.addingTimeInterval(-3600) {
                switch family {
                case .accessoryRectangular:
                    lockScreenLayout(snapshot)
                default:
                    smallLayout(snapshot)
                }
            } else {
                emptyLayout
            }
        }
        .containerBackground(for: .widget) {
            Color(red: 0.05, green: 0.05, blue: 0.08)
        }
    }

    private func lockScreenLayout(_ snapshot: SharedDataStore.NextUpSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: snapshot.iconSystemName)
                    .font(.system(size: 11))
                Text(snapshot.detail.uppercased())
                    .font(.system(size: 10, weight: .semibold))
            }
            .opacity(0.75)

            Text(snapshot.title)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)

            Text(snapshot.date, style: .relative)
                .font(.system(size: 11))
                .opacity(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func smallLayout(_ snapshot: SharedDataStore.NextUpSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: snapshot.iconSystemName)
                    .font(.system(size: 12))
                Text("NEXT UP")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
            }
            .foregroundStyle(Color(red: 0.04, green: 0.52, blue: 1.0))

            Spacer(minLength: 0)

            Text(snapshot.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text(snapshot.date, style: .relative)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.65))

            Text(snapshot.date, format: .dateTime.hour().minute())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0.67, green: 0.78, blue: 1.0))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var emptyLayout: some View {
        VStack(spacing: 6) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.4))
            Text("No upcoming plans")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Widget

struct NextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextUpWidget", provider: NextUpProvider()) { entry in
            NextUpWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Up")
        .description("Your next flight, reservation, or activity.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

@main
struct TravelWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextUpWidget()
    }
}
