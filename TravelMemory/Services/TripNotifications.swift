//
//  TripNotifications.swift
//  TravelMemory
//
//  Local reminders derived from the itinerary: check-in nudges the day
//  before a flight, leave-soon alerts, and day-of reminders for
//  reservations and activities. Rescheduled whenever items change.
//

import Foundation
import UserNotifications

struct TripNotifications {

    // User preferences (Settings tab)
    private static var remindersEnabled: Bool {
        UserDefaults.standard.object(forKey: "remindersEnabled") as? Bool ?? true
    }
    private static var checkinLead: TimeInterval {
        Double(UserDefaults.standard.object(forKey: "checkinLeadHours") as? Int ?? 24) * 3600
    }
    private static var reminderLead: TimeInterval {
        Double(UserDefaults.standard.object(forKey: "reminderLeadHours") as? Int ?? 2) * 3600
    }

    /// Ask once; scheduling is a no-op if the user declines.
    static func requestPermissionIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    // MARK: - Per-item scheduling

    /// Replaces all pending reminders for one item with fresh ones.
    static func resync(item: any ItineraryItem, itemID: UUID) {
        cancel(itemID: itemID)

        // Respect the Settings toggle; ideas aren't commitments either
        guard remindersEnabled, item.status != .idea else { return }

        switch item {
        case let flight as FlightSegment:
            let what = flight.airlineAndFlight.trimmingCharacters(in: .whitespaces)
            let name = what.isEmpty ? "your flight" : what
            let destination = flight.arrivalCity.isEmpty ? flight.arrivalAirport : flight.arrivalCity

            // Online check-in usually opens 24h out; tapping the
            // reminder jumps straight to the airline's check-in page
            let checkInURL = AirlineCheckIn.url(flightNumber: flight.flightNumber, airline: flight.airline)
            var checkinBody = destination.isEmpty ? "Departure coming up." : "To \(destination) — departure coming up."
            if checkInURL != nil { checkinBody += " Tap to open online check-in." }
            schedule(
                id: "\(itemID)-checkin",
                title: "Check in for \(name)",
                body: checkinBody,
                at: flight.departureTime.addingTimeInterval(-checkinLead),
                userInfo: checkInURL.map { ["checkInURL": $0.absoluteString] } ?? [:]
            )
            schedule(
                id: "\(itemID)-leave",
                title: "\(name) departs at \(timeText(flight.departureTime, zone: flight.eventTimeZone(fallback: .current)))",
                body: flight.gate.isEmpty ? "Time to head to the airport." : "Gate \(flight.gate). Time to head to the airport.",
                at: flight.departureTime.addingTimeInterval(-3 * 3600)
            )

        case let dining as DiningReservation:
            let name = dining.restaurantName.isEmpty ? "Dinner reservation" : dining.restaurantName
            schedule(
                id: "\(itemID)-reminder",
                title: "\(name) at \(timeText(dining.reservationTime, zone: dining.eventTimeZone(fallback: .current)))",
                body: dining.address.isEmpty ? "Reservation coming up." : dining.address,
                at: dining.reservationTime.addingTimeInterval(-reminderLead)
            )

        case let activity as TripActivity:
            let name = activity.activityName.isEmpty ? "Activity" : activity.activityName
            schedule(
                id: "\(itemID)-reminder",
                title: "\(name) at \(timeText(activity.startTime, zone: activity.eventTimeZone(fallback: .current)))",
                body: activity.location.isEmpty ? "Starting soon." : activity.location,
                at: activity.startTime.addingTimeInterval(-reminderLead)
            )

        case let car as CarRentalBooking:
            let name = car.company.isEmpty ? "Car rental" : car.company
            schedule(
                id: "\(itemID)-reminder",
                title: "\(name) pickup at \(timeText(car.pickupTime, zone: car.eventTimeZone(fallback: .current)))",
                body: car.pickupLocation.isEmpty ? "Pickup coming up." : car.pickupLocation,
                at: car.pickupTime.addingTimeInterval(-reminderLead)
            )

        default:
            break // hotels generate no reminders — check-in windows are lax
        }
    }

    /// Removes every pending reminder belonging to an item.
    static func cancel(itemID: UUID) {
        let ids = ["\(itemID)-checkin", "\(itemID)-leave", "\(itemID)-reminder"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Reschedules reminders for everything in a trip (used after imports).
    static func resync(trip: Trip) {
        for flight in trip.flights { resync(item: flight, itemID: flight.id) }
        for dining in trip.dining { resync(item: dining, itemID: dining.id) }
        for activity in trip.activities { resync(item: activity, itemID: activity.id) }
        for car in trip.carRentals { resync(item: car, itemID: car.id) }
    }

    // MARK: - Internals

    private static func schedule(id: String, title: String, body: String, at date: Date,
                                 userInfo: [AnyHashable: Any] = [:]) {
        guard date > Date() else { return }

        requestPermissionIfNeeded()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private static func timeText(_ date: Date, zone: TimeZone) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = zone
        return fmt.string(from: date)
    }
}
