//
//  TripAgendaView.swift
//  TravelMemory
//
//  Dense, spreadsheet-like agenda: one row per item, grouped by day,
//  including empty days — the whole trip scannable on one screen.
//

import SwiftUI

// MARK: - Display helpers shared by agenda, exports, and conflict banner

extension ItineraryItem {
    /// Short one-line title for dense listings
    var agendaTitle: String {
        switch self {
        case let flight as FlightSegment:
            let route = flight.routeText.trimmingCharacters(in: .whitespaces)
            let name = flight.airlineAndFlight.trimmingCharacters(in: .whitespaces)
            return [name, route == "→" ? "" : route].filter { !$0.isEmpty }.joined(separator: " · ")
        case let hotel as HotelBooking:
            return hotel.hotelName.isEmpty ? "Accommodation" : hotel.hotelName
        case let car as CarRentalBooking:
            return car.company.isEmpty ? "Car rental" : car.company
        case let dining as DiningReservation:
            return dining.restaurantName.isEmpty ? "Restaurant" : dining.restaurantName
        case let activity as TripActivity:
            return activity.activityName.isEmpty ? "Activity" : activity.activityName
        default:
            return "Item"
        }
    }

    /// The time span this item occupies, for conflict detection
    var occupiedInterval: DateInterval {
        switch self {
        case let flight as FlightSegment:
            return DateInterval(start: flight.departureTime,
                                end: max(flight.arrivalTime, flight.departureTime.addingTimeInterval(60)))
        case let dining as DiningReservation:
            return DateInterval(start: dining.reservationTime, duration: 2 * 3600)
        case let activity as TripActivity:
            return DateInterval(start: activity.startTime,
                                end: max(activity.endTime, activity.startTime.addingTimeInterval(3600)))
        default:
            return DateInterval(start: eventDate, duration: 3600)
        }
    }
}

// MARK: - Agenda View

struct TripAgendaView: View {
    let trip: Trip
    var onEdit: (any ItineraryItem) -> Void

    private func timeText(_ item: any ItineraryItem) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = item.eventTimeZone(fallback: trip.timeZone)
        return f.string(from: item.eventDate)
    }

    private var dayFmt: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        f.timeZone = trip.timeZone
        return f
    }

    /// Every day of the trip (including empty ones) with its items
    private var days: [(day: Date, items: [any ItineraryItem])] {
        let cal = trip.calendar
        let grouped = Dictionary(grouping: trip.timelineItems) { cal.startOfDay(for: $0.eventDate) }

        var result: [(Date, [any ItineraryItem])] = []
        var day = cal.startOfDay(for: min(trip.startDate, grouped.keys.min() ?? trip.startDate))
        let end = cal.startOfDay(for: max(trip.endDate, grouped.keys.max() ?? trip.endDate))
        var guardCounter = 0
        while day <= end && guardCounter < 120 {
            result.append((day, grouped[day] ?? []))
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            guardCounter += 1
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, group in
                daySection(group.day, items: group.items)
            }
        }
        .background(Color.voyagerSurfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerRadius.large)
                .stroke(Color.voyagerOutlineVariant.opacity(0.2), lineWidth: 0.5)
        )
        .padding(.horizontal, VoyagerSpacing.marginMain)
    }

    private func daySection(_ day: Date, items: [any ItineraryItem]) -> some View {
        let isToday = trip.calendar.isDate(day, inSameDayAs: Date())

        return VStack(spacing: 0) {
            // Day header row
            HStack {
                Text(dayFmt.string(from: day).uppercased())
                    .font(VoyagerFont.labelCaps)
                    .tracking(0.8)
                    .foregroundStyle(isToday ? Color.voyagerPrimaryAccent : Color.voyagerOnSurfaceVariant)
                if isToday {
                    Circle()
                        .fill(Color.voyagerPrimaryAccent)
                        .frame(width: 5, height: 5)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.voyagerSurfaceContainerLow)

            if items.isEmpty {
                HStack {
                    Text("nothing planned")
                        .font(.system(size: 12))
                        .italic()
                        .foregroundStyle(Color.voyagerOnSurfaceVariant.opacity(0.5))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    agendaRow(item)
                }
            }
        }
    }

    private func agendaRow(_ item: any ItineraryItem) -> some View {
        Button {
            onEdit(item)
        } label: {
            HStack(spacing: 10) {
                Text(timeText(item))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.voyagerPrimary)
                    .frame(width: 42, alignment: .leading)

                Image(systemName: item.itemType.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    .frame(width: 18)

                Text(item.agendaTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.voyagerOnSurface)
                    .lineLimit(1)

                ItemStatusBadge(status: item.status)

                Spacer()

                if item.cost > 0 {
                    Text("\(Trip.currencySymbol(for: item.currencyCode))\(VoyagerCostField.format(item.cost))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.voyagerTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.voyagerOutlineVariant.opacity(0.12))
                .frame(height: 0.5)
                .padding(.leading, 12)
        }
    }
}
