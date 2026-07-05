//
//  TripExporter.swift
//  TravelMemory
//
//  Turns a trip into shareable formats: plain text (messages/email),
//  a paginated PDF, and an .ics calendar anyone can subscribe to.
//

import Foundation
import SwiftUI
import UIKit

struct TripExporter {

    // MARK: - Plain Text

    static func plainText(for trip: Trip) -> String {
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EEEE, MMM d yyyy"
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"

        var lines: [String] = []
        let title = trip.destination.isEmpty ? trip.name : trip.destination
        lines.append(title.uppercased())
        lines.append("\(trip.dateRangeText) · \(trip.durationDays) day\(trip.durationDays == 1 ? "" : "s")")
        if !trip.budgetText.isEmpty {
            lines.append("Budget so far: \(trip.budgetText)")
        }
        lines.append(String(repeating: "─", count: 32))

        let cal = Calendar.current
        let grouped = Dictionary(grouping: trip.timelineItems) { cal.startOfDay(for: $0.eventDate) }

        for day in grouped.keys.sorted() {
            lines.append("")
            lines.append(dayFmt.string(from: day))
            for item in (grouped[day] ?? []).sorted(by: { $0.eventDate < $1.eventDate }) {
                var line = "  \(timeFmt.string(from: item.eventDate))  \(item.agendaTitle)"
                if item.status != .booked {
                    line += " [\(item.status.label)]"
                }
                if !item.confirmationCode.isEmpty {
                    line += "  ref \(item.confirmationCode)"
                }
                if item.cost > 0 {
                    line += "  \(Trip.currencySymbol(for: item.currencyCode))\(VoyagerCostField.format(item.cost))"
                }
                lines.append(line)

                if let detail = detailLine(for: item), !detail.isEmpty {
                    lines.append("         \(detail)")
                }
            }
        }

        lines.append("")
        lines.append("Shared from Travel Steward")
        return lines.joined(separator: "\n")
    }

    private static func detailLine(for item: any ItineraryItem) -> String? {
        switch item {
        case let flight as FlightSegment:
            var parts: [String] = []
            if !flight.seat.isEmpty { parts.append("seat \(flight.seat)") }
            if !flight.gate.isEmpty { parts.append("gate \(flight.gate)") }
            if !flight.terminal.isEmpty { parts.append("terminal \(flight.terminal)") }
            return parts.joined(separator: ", ")
        case let hotel as HotelBooking:
            return hotel.address
        case let dining as DiningReservation:
            return dining.address
        case let activity as TripActivity:
            return activity.location
        case let car as CarRentalBooking:
            return car.pickupLocation
        default:
            return nil
        }
    }

    // MARK: - ICS

    /// Writes a VCALENDAR of the trip to a temp file and returns its URL.
    static func icsFile(for trip: Trip) -> URL? {
        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Travel Steward//TravelMemory//EN",
            "CALSCALE:GREGORIAN",
        ]

        let stampFmt = DateFormatter()
        stampFmt.locale = Locale(identifier: "en_US_POSIX")
        stampFmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        stampFmt.timeZone = TimeZone(identifier: "UTC")

        let dateOnlyFmt = DateFormatter()
        dateOnlyFmt.locale = Locale(identifier: "en_US_POSIX")
        dateOnlyFmt.dateFormat = "yyyyMMdd"

        for item in trip.timelineItems {
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(UUID().uuidString)@travelsteward")
            lines.append("DTSTAMP:\(stampFmt.string(from: Date()))")

            if let hotel = item as? HotelBooking {
                // All-day span; DTEND is exclusive per RFC 5545
                lines.append("DTSTART;VALUE=DATE:\(dateOnlyFmt.string(from: hotel.checkInDate))")
                lines.append("DTEND;VALUE=DATE:\(dateOnlyFmt.string(from: hotel.checkOutDate))")
            } else {
                lines.append("DTSTART:\(stampFmt.string(from: item.occupiedInterval.start))")
                lines.append("DTEND:\(stampFmt.string(from: item.occupiedInterval.end))")
            }

            lines.append("SUMMARY:\(escape(item.agendaTitle))")
            if let location = detailLine(for: item), !location.isEmpty {
                lines.append("LOCATION:\(escape(location))")
            }
            var description = item.itemType.label.capitalized
            if !item.confirmationCode.isEmpty {
                description += " — confirmation \(item.confirmationCode)"
            }
            lines.append("DESCRIPTION:\(escape(description))")
            lines.append("END:VEVENT")
        }

        lines.append("END:VCALENDAR")

        let content = lines.joined(separator: "\r\n")
        let name = (trip.destination.isEmpty ? trip.name : trip.destination)
            .replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name.isEmpty ? "Trip" : name).ics")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    // MARK: - PDF

    /// Renders the itinerary as a paginated A4 PDF and returns its URL.
    static func pdfFile(for trip: Trip) -> URL? {
        let text = plainText(for: trip)

        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 @72dpi
        let margin: CGFloat = 48
        let textRect = pageRect.insetBy(dx: margin, dy: margin)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)

        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let name = (trip.destination.isEmpty ? trip.name : trip.destination)
            .replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name.isEmpty ? "Trip" : name) Itinerary.pdf")

        do {
            try renderer.writePDF(to: url) { context in
                var currentRange = CFRange(location: 0, length: 0)
                let textLength = attributed.length

                repeat {
                    context.beginPage()
                    let path = CGPath(rect: textRect, transform: nil)
                    let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)

                    // Core Text draws flipped relative to UIKit
                    let cgContext = context.cgContext
                    cgContext.saveGState()
                    cgContext.translateBy(x: 0, y: pageRect.height)
                    cgContext.scaleBy(x: 1, y: -1)
                    CTFrameDraw(frame, cgContext)
                    cgContext.restoreGState()

                    let visible = CTFrameGetVisibleStringRange(frame)
                    currentRange = CFRange(location: visible.location + visible.length, length: 0)
                } while currentRange.location < textLength
            }
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Share Sheet

/// UIActivityViewController wrapper for sharing generated exports.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
