//
//  CalendarSyncService.swift
//  TravelMemory
//
//  Maintains a dedicated "Travel Steward" calendar in the user's iOS
//  Calendar with every booked itinerary item. iCloud then carries it
//  to their other devices and anyone they share that calendar with —
//  the on-device answer to a subscribable feed.
//
//  Sync is a full rebuild: the calendar is exclusively ours, so we
//  wipe it and re-add everything. Cheap at personal-trip scale and
//  immune to drift.
//

import Foundation
import SwiftData
import EventKit

@MainActor
enum CalendarSyncService {

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "calendarSyncEnabled")
    }

    private static let calendarIDKey = "travelStewardCalendarID"
    private static var resyncQueued = false

    // MARK: - Event Building (pure, testable)

    struct PlannedEvent: Equatable {
        var title: String
        var location: String
        var start: Date
        var end: Date
        var isAllDay: Bool
        var timeZoneID: String
        var notes: String
    }

    /// Calendar events for one trip. Ideas are not commitments and
    /// stay out of the calendar.
    static func events(for trip: Trip) -> [PlannedEvent] {
        var planned: [PlannedEvent] = []

        for flight in trip.flights where flight.status != .idea {
            let name = flight.airlineAndFlight.trimmingCharacters(in: .whitespaces)
            let route = [flight.departureAirport, flight.arrivalAirport]
                .filter { !$0.isEmpty }.joined(separator: " → ")
            let title = ["✈️", name.isEmpty ? "Flight" : name, route]
                .filter { !$0.isEmpty }.joined(separator: " ")
            let end = flight.arrivalTime > flight.departureTime
                ? flight.arrivalTime
                : flight.departureTime.addingTimeInterval(2 * 3600)
            planned.append(PlannedEvent(
                title: title,
                location: flight.departureCity.isEmpty ? flight.departureAirport : flight.departureCity,
                start: flight.departureTime, end: end, isAllDay: false,
                timeZoneID: flight.timeZoneID,
                notes: notesLine(seat: flight.seat, gate: flight.gate, confirmation: flight.confirmationCode)
            ))
        }

        for hotel in trip.hotels where hotel.status != .idea {
            planned.append(PlannedEvent(
                title: "🏨 \(hotel.hotelName.isEmpty ? "Accommodation" : hotel.hotelName)",
                location: hotel.address,
                start: hotel.checkInDate, end: hotel.checkOutDate, isAllDay: true,
                timeZoneID: hotel.timeZoneID,
                notes: notesLine(confirmation: hotel.confirmationCode)
            ))
        }

        for car in trip.carRentals where car.status != .idea {
            planned.append(PlannedEvent(
                title: "🚗 \(car.company.isEmpty ? "Car rental" : car.company) pick-up",
                location: car.pickupLocation,
                start: car.pickupTime, end: car.pickupTime.addingTimeInterval(3600), isAllDay: false,
                timeZoneID: car.timeZoneID,
                notes: notesLine(confirmation: car.confirmationCode)
            ))
        }

        for dining in trip.dining where dining.status != .idea {
            planned.append(PlannedEvent(
                title: "🍽️ \(dining.restaurantName.isEmpty ? "Dinner" : dining.restaurantName)",
                location: dining.address,
                start: dining.reservationTime, end: dining.reservationTime.addingTimeInterval(2 * 3600),
                isAllDay: false,
                timeZoneID: dining.timeZoneID,
                notes: notesLine(confirmation: dining.confirmationCode)
            ))
        }

        for activity in trip.activities where activity.status != .idea {
            let end = activity.endTime > activity.startTime
                ? activity.endTime
                : activity.startTime.addingTimeInterval(2 * 3600)
            planned.append(PlannedEvent(
                title: "🎟️ \(activity.activityName.isEmpty ? "Activity" : activity.activityName)",
                location: activity.location,
                start: activity.startTime, end: end, isAllDay: false,
                timeZoneID: activity.timeZoneID,
                notes: notesLine(confirmation: activity.confirmationCode)
            ))
        }

        return planned
    }

    private static func notesLine(seat: String = "", gate: String = "", confirmation: String = "") -> String {
        var parts: [String] = []
        if !seat.isEmpty { parts.append("Seat \(seat)") }
        if !gate.isEmpty { parts.append("Gate \(gate)") }
        if !confirmation.isEmpty { parts.append("Confirmation: \(confirmation)") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Sync

    /// Debounced rebuild — call after any itinerary change; cheap
    /// no-op when the Settings toggle is off.
    static func requestResync(context: ModelContext) {
        guard isEnabled, !resyncQueued else { return }
        resyncQueued = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            resyncQueued = false
            await resyncAll(context: context)
        }
    }

    /// Rebuilds the Travel Steward calendar from every trip.
    static func resyncAll(context: ModelContext) async {
        guard isEnabled else { return }
        // Same guard as calendar import: without the usage key the
        // permission request hangs forever
        guard Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil else { return }

        let store = EKEventStore()
        let granted: Bool = await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, _ in
                DispatchQueue.main.async { continuation.resume(returning: granted) }
            }
        }
        guard granted else { return }

        let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        let planned = trips.flatMap { events(for: $0) }

        do {
            let calendar = try findOrCreateCalendar(in: store)

            // Wipe our calendar (predicates cap at 4 years — plenty)
            let windowStart = Date().addingTimeInterval(-365 * 24 * 3600)
            let windowEnd = Date().addingTimeInterval(3 * 365 * 24 * 3600)
            let predicate = store.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: [calendar])
            for event in store.events(matching: predicate) {
                try? store.remove(event, span: .thisEvent, commit: false)
            }

            for p in planned {
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                event.title = p.title
                event.location = p.location.isEmpty ? nil : p.location
                event.startDate = p.start
                event.endDate = p.end
                event.isAllDay = p.isAllDay
                if let zone = TimeZone(identifier: p.timeZoneID) { event.timeZone = zone }
                event.notes = p.notes.isEmpty ? nil : p.notes
                try? store.save(event, span: .thisEvent, commit: false)
            }

            try store.commit()
        } catch {
            print("⚠️ Calendar sync failed: \(error)")
        }
    }

    /// Turns sync off and removes our calendar — the user asked for
    /// their calendar back, don't leave stale events behind.
    static func disable() {
        UserDefaults.standard.set(false, forKey: "calendarSyncEnabled")
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let id = UserDefaults.standard.string(forKey: calendarIDKey) else { return }
        let store = EKEventStore()
        if let calendar = store.calendar(withIdentifier: id) {
            try? store.removeCalendar(calendar, commit: true)
        }
        UserDefaults.standard.removeObject(forKey: calendarIDKey)
    }

    // MARK: - Calendar plumbing

    private static func findOrCreateCalendar(in store: EKEventStore) throws -> EKCalendar {
        if let id = UserDefaults.standard.string(forKey: calendarIDKey),
           let existing = store.calendar(withIdentifier: id) {
            return existing
        }

        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Travel Steward"
        calendar.cgColor = CGColor(red: 0.35, green: 0.55, blue: 1.0, alpha: 1.0)
        // iCloud source if there is one, so the calendar follows the
        // user across devices; otherwise wherever new events go
        let sources = store.sources
        calendar.source = sources.first { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") }
            ?? store.defaultCalendarForNewEvents?.source
            ?? sources.first { $0.sourceType == .local }

        try store.saveCalendar(calendar, commit: true)
        UserDefaults.standard.set(calendar.calendarIdentifier, forKey: calendarIDKey)
        return calendar
    }
}
