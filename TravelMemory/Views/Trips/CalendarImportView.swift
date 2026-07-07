//
//  CalendarImportView.swift
//  TravelMemory
//
//  Imports bookings that live as events in the iOS Calendar app —
//  Booking.com's "add to calendar", synced Gmail events, and friends.
//  Lists everything in the trip's date range; the user picks which
//  events to bring in, and they flow through the usual review screen.
//

import SwiftUI
import EventKit

struct CalendarImportView: View {
    let trip: Trip
    var onImport: (EmailParser.ParseResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var events: [EKEvent] = []
    @State private var selectedIDs: Set<String> = []
    @State private var accessDenied = false
    @State private var loaded = false

    private let store = EKEventStore()

    private var rowFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM · HH:mm"
        f.timeZone = trip.timeZone
        return f
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.voyagerBackground.ignoresSafeArea()

                if accessDenied {
                    deniedState
                } else if !loaded {
                    ProgressView()
                        .tint(Color.voyagerPrimary)
                } else if events.isEmpty {
                    emptyState
                } else {
                    eventList
                }
            }
            .navigationTitle("Import from Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await loadEvents() }
    }

    // MARK: - States

    private var deniedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(Color.voyagerTertiary)
            Text("Calendar access needed")
                .font(VoyagerFont.headlineMedium)
                .foregroundStyle(Color.voyagerOnSurface)
            Text("Allow calendar access in Settings → Travel Steward to import booking events.")
                .font(VoyagerFont.bodySmall)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 40))
                .foregroundStyle(Color.voyagerOnSurfaceVariant.opacity(0.5))
            Text("Nothing in this trip's dates")
                .font(VoyagerFont.headlineMedium)
                .foregroundStyle(Color.voyagerOnSurface)
            Text("No calendar events found between \(trip.dateRangeText).")
                .font(VoyagerFont.bodySmall)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Event List

    private var eventList: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    Text("Pick the bookings to add — recurring events (like weekly meetings) start unticked.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)

                    ForEach(events, id: \.eventIdentifier) { event in
                        eventRow(event)
                    }
                }
                .padding(.horizontal, VoyagerSpacing.marginMain)
                .padding(.bottom, 12)
            }

            Button {
                importSelected()
            } label: {
                Text("IMPORT \(selectedIDs.count) EVENT\(selectedIDs.count == 1 ? "" : "S")")
            }
            .buttonStyle(VoyagerPrimaryButtonStyle())
            .disabled(selectedIDs.isEmpty)
            .opacity(selectedIDs.isEmpty ? 0.5 : 1)
            .padding(.horizontal, VoyagerSpacing.marginMain)
            .padding(.bottom, 16)
        }
    }

    private func eventRow(_ event: EKEvent) -> some View {
        let isSelected = selectedIDs.contains(event.eventIdentifier)

        return Button {
            if isSelected {
                selectedIDs.remove(event.eventIdentifier)
            } else {
                selectedIDs.insert(event.eventIdentifier)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.voyagerPrimaryAccent : Color.voyagerOutlineVariant)

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title ?? "Untitled event")
                        .font(VoyagerFont.bodyMedium)
                        .foregroundStyle(Color.voyagerOnSurface)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let start = event.startDate {
                            Text(event.isAllDay
                                 ? rowFormatter.string(from: start).components(separatedBy: " · ").first ?? ""
                                 : rowFormatter.string(from: start))
                                .font(.system(size: 12))
                        }
                        if let calendar = event.calendar {
                            Text("· \(calendar.title)")
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }

                Spacer()

                if let cgColor = event.calendar?.cgColor {
                    Circle()
                        .fill(Color(cgColor: cgColor))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(12)
            .background(Color.voyagerSurfaceContainerLow)
            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                    .stroke(isSelected ? Color.voyagerPrimaryAccent.opacity(0.4) : Color.voyagerOutlineVariant.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - EventKit

    private func loadEvents() async {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        guard granted else {
            accessDenied = true
            return
        }

        // The trip's dates, padded a day each side for overnight arrivals
        let start = trip.startDate.addingTimeInterval(-24 * 3600)
        let end = trip.endDate.addingTimeInterval(48 * 3600)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let found = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        events = found
        // Bookings are one-off events; recurring ones (standups, gym)
        // are almost never itinerary items, so they start unticked
        selectedIDs = Set(found.filter { !$0.hasRecurrenceRules }.compactMap(\.eventIdentifier))
        loaded = true
    }

    private func importSelected() {
        let chosen = events.filter { selectedIDs.contains($0.eventIdentifier) }
        let mapped = chosen.map { event in
            ICSParser.Event(
                summary: event.title ?? "",
                location: event.location ?? "",
                details: event.notes ?? "",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                startTimeZoneID: event.timeZone?.identifier ?? "",
                endTimeZoneID: event.timeZone?.identifier ?? ""
            )
        }
        let result = ICSParser.parseResult(from: mapped)
        dismiss()
        onImport(result)
    }
}
