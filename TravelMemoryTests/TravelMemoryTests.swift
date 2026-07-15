//
//  TravelMemoryTests.swift
//  TravelMemoryTests
//
//  Fixture-based tests for the email parser — the most failure-prone
//  and most testable component in the app.
//

import Foundation
import SwiftData
import Testing
import UIKit
@testable import TravelMemory

struct EmailParserFlightTests {

    private let flightEmailBody = """
        Dear Passenger,

        Your flight has been confirmed.

        Flight: Lufthansa LH411
        Date: Oct 12, 2025

        Departure: JFK (New York) at 18:30
        Arrival: MUC (Munich) at 08:15

        Gate: D4
        Seat: 14A

        Booking Reference: ABCX7K

        We wish you a pleasant journey!
        Lufthansa Customer Service
        """

    @Test func parsesFlightDetailsFromConfirmationEmail() throws {
        let result = EmailParser.parse(
            subject: "Your Flight Confirmation - LH411",
            body: flightEmailBody,
            sender: "noreply@lufthansa.com"
        )

        #expect(result.flights.count == 1)
        let flight = try #require(result.flights.first)
        #expect(flight.airline == "Lufthansa")
        #expect(flight.flightNumber == "LH411")
        #expect(flight.departureAirport == "JFK")
        #expect(flight.arrivalAirport == "MUC")
        #expect(flight.gate == "D4")
        #expect(flight.seat == "14A")
    }

    @Test func extractsConfirmationCode() {
        // Regression: the previous implementation uppercased the text but
        // matched case-sensitive lowercase keywords, so no code ever matched.
        let result = EmailParser.parse(
            subject: "Your Flight Confirmation - LH411",
            body: flightEmailBody,
            sender: "noreply@lufthansa.com"
        )

        #expect(result.flights.first?.confirmationCode == "ABCX7K")
    }

    @Test func extractsDepartureDateWithTime() throws {
        let result = EmailParser.parse(
            subject: "Your Flight Confirmation - LH411",
            body: flightEmailBody,
            sender: "noreply@lufthansa.com"
        )

        let departure = try #require(result.flights.first?.departureTime)
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: departure)
        #expect(comps.year == 2025)
        #expect(comps.month == 10)
        #expect(comps.day == 12)
        #expect(comps.hour == 18)
        #expect(comps.minute == 30)
    }

    @Test func pairsTimesWithDatesInDocumentOrderAcrossFormats() throws {
        // Regression: dates used to be collected grouped by format, so a
        // mixed-format email paired the first time with the wrong date.
        let body = """
            Flight LH100 is confirmed.
            Departure: 2025-10-14 at 18:30 from FRA
            Arrival: Oct 15, 2025 at 06:15 in SIN
            """
        let result = EmailParser.parse(
            subject: "Flight confirmation",
            body: body,
            sender: "noreply@lufthansa.com"
        )

        let flight = try #require(result.flights.first)
        let cal = Calendar.current

        let dep = try #require(flight.departureTime)
        #expect(cal.component(.day, from: dep) == 14)
        #expect(cal.component(.hour, from: dep) == 18)

        let arr = try #require(flight.arrivalTime)
        #expect(cal.component(.day, from: arr) == 15)
        #expect(cal.component(.hour, from: arr) == 6)
    }

    @Test func prefersKnownAirlineDesignatorForFlightNumber() {
        // "PO 1234" appears first but is not a known designator.
        let body = "Ref PO 1234. Your Lufthansa flight LH 411 departs JFK for MUC on Oct 12, 2025."
        let result = EmailParser.parse(
            subject: "Flight confirmation",
            body: body,
            sender: "noreply@lufthansa.com"
        )

        #expect(result.flights.first?.flightNumber == "LH411")
    }

    @Test func parsesRoundTripWithTwoSegments() throws {
        // A Booking.com-style confirmation with outbound and return legs
        // must produce two flight segments, not one.
        let body = """
            Your flight booking is confirmed.

            Outbound flight
            Ryanair FR 1885
            London Stansted (STN) to Munich (MUC)
            Departure: Oct 12, 2025 at 06:25
            Arrival: Oct 12, 2025 at 09:20

            Return flight
            Ryanair FR 1886
            Munich (MUC) to London Stansted (STN)
            Departure: Oct 18, 2025 at 21:35
            Arrival: Oct 18, 2025 at 22:30

            Booking Reference: ABCX7K
            """
        let result = EmailParser.parse(
            subject: "Your flight booking - FR1885",
            body: body,
            sender: "noreply@booking.com"
        )

        #expect(result.flights.count == 2)
        let outbound = try #require(result.flights.first)
        let inbound = try #require(result.flights.last)
        let cal = Calendar.current

        #expect(outbound.flightNumber == "FR1885")
        #expect(outbound.departureAirport == "STN")
        #expect(outbound.arrivalAirport == "MUC")
        let outboundDep = try #require(outbound.departureTime)
        #expect(cal.component(.day, from: outboundDep) == 12)

        #expect(inbound.flightNumber == "FR1886")
        #expect(inbound.departureAirport == "MUC")
        #expect(inbound.arrivalAirport == "STN")
        let inboundDep = try #require(inbound.departureTime)
        #expect(cal.component(.day, from: inboundDep) == 18)
        #expect(cal.component(.hour, from: inboundDep) == 21)
    }

    @Test func lowercaseWordsAreNotMistakenForAirportCodes() {
        // Regression: the text used to be uppercased before matching, so
        // ordinary words ("our", "trip") became airport-code candidates.
        let body = "We hope our tips for you and yours are fun for the big day out."
        let result = EmailParser.parse(
            subject: "Flight news",
            body: body + "\nflight depart arrive",
            sender: "someone@example.org"
        )

        if let flight = result.flights.first {
            #expect(flight.departureAirport.isEmpty)
            #expect(flight.arrivalAirport.isEmpty)
        }
    }
}

struct EmailParserHotelTests {

    private let hotelEmailBody = """
        Your reservation is confirmed.

        Hotel: Hotel Vier Jahreszeiten Kempinski
        Address: Maximilianstrasse 17, 80539 Munich
        Check-in: Oct 12, 2025
        Check-out: Oct 18, 2025
        Confirmation: KMP884920

        We look forward to welcoming you.
        """

    @Test func parsesHotelBookingEmail() throws {
        let result = EmailParser.parse(
            subject: "Your hotel booking is confirmed",
            body: hotelEmailBody,
            sender: "reservations@kempinski.com"
        )

        #expect(result.hotels.count == 1)
        let hotel = try #require(result.hotels.first)

        // Full name around the brand, not just "Kempinski"
        #expect(hotel.hotelName == "Hotel Vier Jahreszeiten Kempinski")

        let cal = Calendar.current
        let checkIn = try #require(hotel.checkIn)
        let checkOut = try #require(hotel.checkOut)
        #expect(cal.component(.day, from: checkIn) == 12)
        #expect(cal.component(.day, from: checkOut) == 18)
    }

    @Test func extractsLongConfirmationCode() {
        // Regression: codes longer than 8 characters used to be truncated.
        let result = EmailParser.parse(
            subject: "Your hotel booking is confirmed",
            body: hotelEmailBody,
            sender: "reservations@kempinski.com"
        )

        #expect(result.hotels.first?.confirmationCode == "KMP884920")
    }
}

struct EmailParserCarRentalTests {

    @Test func parsesCarRentalEmail() throws {
        let body = """
            Car Rental: Sixt Rent a Car
            Vehicle: BMW 5 Series or similar
            Pickup: Oct 12, 2025 at 15:30
            Dropoff: Oct 18, 2025 at 10:00
            Reservation: SX884920
            Pre-paid
            """
        let result = EmailParser.parse(
            subject: "Your car rental confirmation",
            body: body,
            sender: "noreply@sixt.com"
        )

        #expect(result.carRentals.count == 1)
        let car = try #require(result.carRentals.first)
        #expect(car.company == "Sixt")
        #expect(car.vehicleType == "BMW")
        #expect(car.isPrepaid)
        #expect(car.confirmationCode == "SX884920")

        let cal = Calendar.current
        let pickup = try #require(car.pickupTime)
        let dropoff = try #require(car.dropoffTime)
        #expect(cal.component(.day, from: pickup) == 12)
        #expect(cal.component(.hour, from: pickup) == 15)
        #expect(cal.component(.day, from: dropoff) == 18)
        #expect(cal.component(.hour, from: dropoff) == 10)
    }
}

struct ICSParserTests {

    private let calendarFixture = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Booking.com//EN
        BEGIN:VEVENT
        UID:1@booking.com
        DTSTART;TZID=Europe/London:20251012T062500
        DTEND;TZID=Europe/Berlin:20251012T092000
        SUMMARY:Flight to Munich FR 1885
        LOCATION:London Stansted (STN)
        DESCRIPTION:Ryanair FR 1885 from STN to MUC\\nBooking Reference: ABCX7K
        END:VEVENT
        BEGIN:VEVENT
        UID:2@booking.com
        DTSTART;VALUE=DATE:20251012
        DTEND;VALUE=DATE:20251018
        SUMMARY:Stay at Hotel Vier Jahreszeiten Kempinski
        LOCATION:Maximilianstrasse 17\\, 80539 Munich
        END:VEVENT
        BEGIN:VEVENT
        UID:3@opentable.com
        DTSTART;TZID=Europe/Berlin:20251013T193000
        DTEND;TZID=Europe/Berlin:20251013T213000
        SUMMARY:Dinner at Tantris - table for 4
        LOCATION:Johann-Fichte-Strasse 7\\, Munich
        END:VEVENT
        END:VCALENDAR
        """

    /// Expected timestamp built independently of the device timezone.
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, zone: String) throws -> Date {
        var components = DateComponents()
        (components.year, components.month, components.day) = (year, month, day)
        (components.hour, components.minute) = (hour, minute)
        components.timeZone = try #require(TimeZone(identifier: zone))
        return try #require(Calendar(identifier: .gregorian).date(from: components))
    }

    @Test func calendarContentIsRoutedToICSParser() {
        // Entry point used by paste, share, and file import alike
        let result = EmailIngestionService.parse(subject: "whatever.ics", body: calendarFixture, sender: "")
        #expect(result.flights.count == 1)
        #expect(result.hotels.count == 1)
        #expect(result.dining.count == 1)
        #expect(result.activities.isEmpty)
        #expect(result.overallConfidence > 0.7)
    }

    @Test func flightEventUsesExactTimesAndTimezones() throws {
        let result = ICSParser.parse(calendarFixture)
        let flight = try #require(result.flights.first)

        #expect(flight.flightNumber == "FR1885")
        #expect(flight.airline == "Ryanair")
        #expect(flight.departureAirport == "STN")
        #expect(flight.arrivalAirport == "MUC")
        #expect(flight.confirmationCode == "ABCX7K")

        // DTSTART/DTEND are authoritative, including their TZIDs
        let expectedDeparture = try date(2025, 10, 12, 6, 25, zone: "Europe/London")
        let expectedArrival = try date(2025, 10, 12, 9, 20, zone: "Europe/Berlin")
        #expect(flight.departureTime == expectedDeparture)
        #expect(flight.arrivalTime == expectedArrival)

        // The TZIDs themselves ride along, so the app can display
        // event-local wall time regardless of the device zone
        #expect(flight.departureTimeZoneID == "Europe/London")
        #expect(flight.arrivalTimeZoneID == "Europe/Berlin")
    }

    @Test func allDayHotelEventBecomesBooking() throws {
        let result = ICSParser.parse(calendarFixture)
        let hotel = try #require(result.hotels.first)

        // "Stay at" prefix stripped, escaped comma unescaped
        #expect(hotel.hotelName == "Hotel Vier Jahreszeiten Kempinski")
        #expect(hotel.address == "Maximilianstrasse 17, 80539 Munich")

        let cal = Calendar.current
        let checkIn = try #require(hotel.checkIn)
        let checkOut = try #require(hotel.checkOut)
        #expect(cal.component(.day, from: checkIn) == 12)
        #expect(cal.component(.day, from: checkOut) == 18)
    }

    @Test func dinnerEventBecomesDiningReservation() throws {
        let result = ICSParser.parse(calendarFixture)
        let dining = try #require(result.dining.first)

        #expect(dining.restaurantName.hasPrefix("Tantris"))
        #expect(dining.partySize == 4)
        let expectedTime = try date(2025, 10, 13, 19, 30, zone: "Europe/Berlin")
        #expect(dining.reservationTime == expectedTime)
    }

    @Test func bookingHotelCalendarEventIsNotAFlight() throws {
        // Regression: Booking.com hotel calendar events keep the whole
        // reservation in the notes — postcode tokens ("W6 9XX") faked
        // flight numbers and produced empty 90%-confidence flights
        let event = ICSParser.Event(
            summary: "Bergblick Garni",
            location: "Bergstrasse 12, Garmisch",
            details: "Check-in: 15 October 2025 (from 15:00)\nCheck-out: 18 October 2025\nConfirmation: 3712.456.789\nOffice: W6 9XX London",
            start: Date(timeIntervalSince1970: 1_760_000_000),
            end: Date(timeIntervalSince1970: 1_760_250_000),
            isAllDay: true
        )
        let result = ICSParser.parseResult(from: [event])

        #expect(result.flights.isEmpty)
        #expect(result.hotels.count == 1)
        let hotel = try #require(result.hotels.first)
        #expect(hotel.hotelName == "Bergblick Garni")
        #expect(hotel.confirmationCode == "3712.456.789")
    }

    @Test func flightTitledCalendarEventStillClassifiesAsFlight() {
        let event = ICSParser.Event(
            summary: "Flight to Munich FR1885",
            location: "London Stansted",
            details: "",
            start: Date(timeIntervalSince1970: 1_760_000_000),
            end: Date(timeIntervalSince1970: 1_760_010_000),
            isAllDay: false
        )
        let result = ICSParser.parseResult(from: [event])
        #expect(result.flights.count == 1)
        #expect(result.flights.first?.flightNumber == "FR1885")
    }

    @Test func foldedLinesAndUTCTimesAreHandled() throws {
        // SUMMARY folded across two lines (RFC 5545), DTSTART in UTC
        let fixture = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDTSTART:20251014T100000Z\r\nSUMMARY:Guided tour of the old\r\n  town and market\r\nEND:VEVENT\r\nEND:VCALENDAR"

        let events = ICSParser.parseEvents(from: fixture)
        let event = try #require(events.first)
        #expect(event.summary == "Guided tour of the old town and market")
        let expectedStart = try date(2025, 10, 14, 10, 0, zone: "UTC")
        #expect(event.start == expectedStart)
    }

    @Test func nonCalendarTextIsNotDetectedAsCalendar() {
        #expect(!ICSParser.isCalendar("Just a regular booking email about your flight"))
        #expect(ICSParser.isCalendar(calendarFixture))
    }
}

struct CSVImporterTests {

    @Test func tokenizerHandlesQuotedFieldsAndSemicolons() {
        let csv = "name;cost\n\"Restaurant; fancy\";\"1.234,50\""
        let rows = CSVImporter.rows(from: csv)
        #expect(rows.count == 2)
        #expect(rows[1][0] == "Restaurant; fancy")

        let quoted = CSVImporter.rows(from: "a,b\n\"x, y\",\"he said \"\"hi\"\"\"")
        #expect(quoted[1][0] == "x, y")
        #expect(quoted[1][1] == "he said \"hi\"")
    }

    @Test func importsSpreadsheetItinerary() throws {
        let csv = """
            Date,Time,Type,Name,Location,Cost,Notes
            2025-10-12,06:25,Flight,FR 1885 STN to MUC,Stansted,£45,hand luggage only
            2025-10-12,,Hotel,Hotel Vier Jahreszeiten,Munich,€890,
            2025-10-13,19:30,Dinner,Tantris,Munich,,tasting menu
            2025-10-14,10:00,,Old town walking tour,Marienplatz,€15,
            """
        let result = CSVImporter.parse(csv)

        #expect(result.flights.count == 1)
        #expect(result.hotels.count == 1)
        #expect(result.dining.count == 1)
        #expect(result.activities.count == 1)

        let flight = try #require(result.flights.first)
        #expect(flight.flightNumber == "FR1885")
        #expect(flight.cost == 45)
        #expect(flight.currencyCode == "GBP")
        let dep = try #require(flight.departureTime)
        let cal = Calendar.current
        #expect(cal.component(.day, from: dep) == 12)
        #expect(cal.component(.hour, from: dep) == 6)

        let hotel = try #require(result.hotels.first)
        #expect(hotel.hotelName == "Hotel Vier Jahreszeiten")
        #expect(hotel.cost == 890)
        #expect(hotel.currencyCode == "EUR")

        #expect(result.dining.first?.restaurantName == "Tantris")
        #expect(result.activities.first?.activityName == "Old town walking tour")
        #expect(result.activities.first?.cost == 15)
    }

    @Test func unusableFileReportsIssue() {
        let result = CSVImporter.parse("just some text without structure")
        #expect(result.overallConfidence <= 0.2)
        #expect(!result.issues.isEmpty)
    }
}

struct GoogleMapsLinkParserTests {

    @Test func parsesPlaceURLWithDataBlob() throws {
        // The !3d/!4d pair is the precise pin — preferred over the
        // viewport center after the @
        let url = try #require(URL(string:
            "https://www.google.com/maps/place/Tantris+Maison+Culinaire/@48.161,11.58,15z/data=!4m6!3m5!1s0x479e75!8m2!3d48.1631899!4d11.5865861!16s"))
        let place = try #require(GoogleMapsLinkParser.parsePlace(from: url))
        #expect(place.name == "Tantris Maison Culinaire")
        #expect(place.latitude != nil)
        #expect(abs((place.latitude ?? 0) - 48.1631899) < 0.0001)
    }

    @Test func parsesPlaceURLWithViewportOnly() throws {
        let url = try #require(URL(string:
            "https://www.google.com/maps/place/Caf%C3%A9+Luitpold/@48.1417,11.5731,17z"))
        let place = try #require(GoogleMapsLinkParser.parsePlace(from: url))
        #expect(place.name == "Café Luitpold")
        #expect(abs((place.latitude ?? 0) - 48.1417) < 0.0001)
        #expect(abs((place.longitude ?? 0) - 11.5731) < 0.0001)
    }

    @Test func parsesQueryStyleLink() throws {
        let url = try #require(URL(string:
            "https://www.google.com/maps/search/?api=1&query=Hofbr%C3%A4uhaus+M%C3%BCnchen"))
        let place = try #require(GoogleMapsLinkParser.parsePlace(from: url))
        #expect(place.name == "Hofbräuhaus München")
    }

    @Test func searchAndDirectionsURLsAreNotPlaces() throws {
        // Browsing the results list or directions must not trigger the
        // capture bar
        let search = try #require(URL(string: "https://www.google.com/maps/search/restaurants/@48.14,11.57,15z"))
        #expect(GoogleMapsLinkParser.parsePlace(from: search) == nil)

        let home = try #require(URL(string: "https://www.google.com/maps/@48.14,11.57,15z"))
        #expect(GoogleMapsLinkParser.parsePlace(from: home) == nil)
    }

    @Test func sharedMapsLinkBecomesDiningImport() async throws {
        // Sharing a restaurant from Google Maps must route to a dining
        // item, not a meaningless email parse (previous behavior).
        let body = "Look at this https://www.google.com/maps/place/Tantris/@48.161,11.58,15z/data=!3d48.1631899!4d11.5865861"
        let result = await EmailIngestionService.parseContent(subject: "Shared Content", body: body, sender: "")

        #expect(result.dining.count == 1)
        #expect(result.dining.first?.restaurantName == "Tantris")
        #expect(result.flights.isEmpty)
        #expect(result.overallConfidence > 0.7)
    }

    @Test func detectsMapsLinksInSharedText() {
        #expect(GoogleMapsLinkParser.isMapsLink("Check this out https://maps.app.goo.gl/AbC123"))
        #expect(GoogleMapsLinkParser.isMapsLink("https://www.google.com/maps/place/Tantris"))
        #expect(!GoogleMapsLinkParser.isMapsLink("https://apple.com/maps-is-not-google"))
        #expect(!GoogleMapsLinkParser.isMapsLink("just some text"))
    }
}

@MainActor
struct DuplicateImportTests {

    // Standalone model graph — hosted tests can't spin up a second
    // SwiftData container next to the app's, and the matching logic
    // doesn't need one.
    private func makeTripWithExistingBookings() -> Trip {
        let trip = Trip(
            name: "Munich Trip", destination: "Munich",
            startDate: Date(timeIntervalSince1970: 1760227200), // Oct 12 2025
            endDate: Date(timeIntervalSince1970: 1760745600)
        )
        let flight = FlightSegment(
            airline: "Lufthansa", flightNumber: "LH411",
            departureAirport: "JFK", departureCity: "New York",
            arrivalAirport: "MUC", arrivalCity: "Munich",
            departureTime: Date(timeIntervalSince1970: 1760292600), // Oct 12 2025 18:30 UTC
            confirmationCode: "ABCX7K"
        )
        trip.flights.append(flight)

        let hotel = HotelBooking(
            hotelName: "Hotel Vier Jahreszeiten Kempinski",
            checkInDate: Date(timeIntervalSince1970: 1760227200),
            checkOutDate: Date(timeIntervalSince1970: 1760745600)
        )
        trip.hotels.append(hotel)
        return trip
    }

    private var flightEmail: (subject: String, body: String, sender: String) {
        ("Your Flight Confirmation - LH411", """
            Flight: Lufthansa LH411
            Date: Oct 12, 2025
            Departure: JFK (New York) at 18:30
            Arrival: MUC (Munich) at 08:15
            Booking Reference: ABCX7K
            """, "noreply@lufthansa.com")
    }

    @Test func reimportedFlightIsFlaggedAsDuplicate() {
        let trip = makeTripWithExistingBookings()
        let email = flightEmail
        let result = EmailParser.parse(subject: email.subject, body: email.body, sender: email.sender)

        let warnings = EmailIngestionService.duplicateDescriptions(in: result, against: trip)
        #expect(warnings.contains { $0.contains("LH411") })
    }

    @Test func reimportedHotelIsFlaggedAsDuplicate() {
        let trip = makeTripWithExistingBookings()
        let result = EmailParser.parse(
            subject: "Your hotel booking is confirmed",
            body: """
                Hotel: Hotel Vier Jahreszeiten Kempinski
                Check-in: Oct 12, 2025
                Check-out: Oct 18, 2025
                Confirmation: KMP884920
                """,
            sender: "reservations@kempinski.com"
        )

        let warnings = EmailIngestionService.duplicateDescriptions(in: result, against: trip)
        #expect(warnings.contains { $0.contains("Kempinski") })
    }

    @Test func differentFlightIsNotFlaggedAsDuplicate() {
        let trip = makeTripWithExistingBookings()
        let other = EmailParser.parse(
            subject: "Your Flight Confirmation - LH410",
            body: """
                Flight: Lufthansa LH410
                Date: Oct 18, 2025
                Departure: MUC (Munich) at 21:35
                Arrival: JFK (New York) at 23:30
                Booking Reference: XYZ99Q
                """,
            sender: "noreply@lufthansa.com"
        )

        let warnings = EmailIngestionService.duplicateDescriptions(in: other, against: trip)
        #expect(warnings.isEmpty)
    }
}

@MainActor
struct CalendarSyncBuilderTests {

    @Test func buildsEventsForBookedItemsOnly() throws {
        let trip = Trip(name: "Munich", destination: "Munich",
                        startDate: Date(timeIntervalSince1970: 1_760_000_000),
                        endDate: Date(timeIntervalSince1970: 1_760_500_000))

        let flight = FlightSegment(airline: "Ryanair", flightNumber: "FR1885",
                                   departureAirport: "STN", arrivalAirport: "MUC",
                                   departureTime: Date(timeIntervalSince1970: 1_760_010_000),
                                   arrivalTime: Date(timeIntervalSince1970: 1_760_020_000),
                                   seat: "14A")
        flight.timeZoneID = "Europe/London"
        trip.flights.append(flight)

        let hotel = HotelBooking(hotelName: "Bergblick Garni",
                                 checkInDate: Date(timeIntervalSince1970: 1_760_020_000),
                                 checkOutDate: Date(timeIntervalSince1970: 1_760_400_000))
        trip.hotels.append(hotel)

        let idea = DiningReservation(restaurantName: "Tantris")
        idea.status = .idea
        trip.dining.append(idea)

        let events = CalendarSyncService.events(for: trip)

        #expect(events.count == 2) // idea stays out of the calendar

        let flightEvent = try #require(events.first { $0.title.contains("FR1885") })
        #expect(flightEvent.title.contains("STN → MUC"))
        #expect(flightEvent.isAllDay == false)
        #expect(flightEvent.timeZoneID == "Europe/London")
        #expect(flightEvent.notes.contains("Seat 14A"))

        let hotelEvent = try #require(events.first { $0.title.contains("Bergblick") })
        #expect(hotelEvent.isAllDay == true)
        #expect(hotelEvent.start == hotel.checkInDate)
        #expect(hotelEvent.end == hotel.checkOutDate)
    }

    @Test func zeroLengthTimesGetSensibleDurations() {
        let trip = Trip(name: "T", destination: "",
                        startDate: .now, endDate: .now)
        let sameInstant = Date(timeIntervalSince1970: 1_760_000_000)
        let flight = FlightSegment(flightNumber: "LH411",
                                   departureTime: sameInstant, arrivalTime: sameInstant)
        trip.flights.append(flight)

        let events = CalendarSyncService.events(for: trip)
        #expect(events.first.map { $0.end > $0.start } == true)
    }
}

struct AirlineCheckInTests {

    @Test func resolvesCheckInURLFromFlightNumberDesignator() throws {
        let url = try #require(AirlineCheckIn.url(flightNumber: "FR1885", airline: ""))
        #expect(url.absoluteString.contains("ryanair.com"))

        // Alphanumeric designators like Wizz Air's W6 work too
        let wizz = try #require(AirlineCheckIn.url(flightNumber: "W6 2301", airline: ""))
        #expect(wizz.absoluteString.contains("wizzair.com"))
    }

    @Test func fallsBackToAirlineNameWhenNumberIsMissing() throws {
        let url = try #require(AirlineCheckIn.url(flightNumber: "", airline: "British Airways"))
        #expect(url.absoluteString.contains("britishairways.com"))
    }

    @Test func unknownAirlineYieldsNoURL() {
        #expect(AirlineCheckIn.url(flightNumber: "ZZ999", airline: "Air Nowhere") == nil)
        #expect(AirlineCheckIn.url(flightNumber: "1885", airline: "") == nil)
    }
}

@MainActor
struct BackupServiceTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Trip.self, FlightSegment.self, HotelBooking.self, CarRentalBooking.self,
            ParsedEmail.self, PackingCategoryModel.self, PackingItemModel.self,
            VaultDocument.self, DiningReservation.self, TripActivity.self,
        ])
        // .none explicitly: the entitled test host would otherwise try
        // CloudKit (.automatic default), which in-memory stores can't do
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func seedTrip(in context: ModelContext) -> Trip {
        let trip = Trip(name: "Munich Trip", destination: "Munich",
                        startDate: Date(timeIntervalSince1970: 1_760_000_000),
                        endDate: Date(timeIntervalSince1970: 1_760_500_000))
        trip.timeZoneID = "Europe/Berlin"
        trip.isArchived = true
        context.insert(trip)

        let flight = FlightSegment(airline: "Ryanair", flightNumber: "FR1885",
                                   departureAirport: "STN", arrivalAirport: "MUC",
                                   seat: "14A", confirmationCode: "ABCX7K")
        flight.cost = 45
        flight.currencyCode = "GBP"
        flight.timeZoneID = "Europe/London"
        flight.arrivalTimeZoneID = "Europe/Berlin"
        flight.boardingPassData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        trip.flights.append(flight)

        let dining = DiningReservation(restaurantName: "Tantris", phone: "+49 89 123")
        dining.status = .idea
        trip.dining.append(dining)

        let category = PackingCategoryModel(name: "Essentials")
        category.items.append(PackingItemModel(name: "Passport", isPacked: true))
        trip.packingCategories.append(category)

        let document = VaultDocument(title: "Passport", categoryRaw: "passport",
                                     imageData: Data([1, 2, 3]))
        context.insert(document)
        return trip
    }

    @Test func roundTripPreservesEverything() throws {
        let source = try makeContainer()
        let trip = seedTrip(in: source.mainContext)
        try source.mainContext.save()

        let url = try BackupService.export(context: source.mainContext)

        // Fresh, empty database — the post-reinstall scenario
        let target = try makeContainer()
        let summary = try BackupService.restore(from: url, context: target.mainContext)

        #expect(summary.tripsRestored == 1)
        #expect(summary.documentsRestored == 1)

        let trips = try target.mainContext.fetch(FetchDescriptor<Trip>())
        let restored = try #require(trips.first)
        #expect(restored.id == trip.id)
        #expect(restored.timeZoneID == "Europe/Berlin")
        #expect(restored.isArchived == true)

        let flight = try #require(restored.flights.first)
        #expect(flight.flightNumber == "FR1885")
        #expect(flight.cost == 45)
        #expect(flight.timeZoneID == "Europe/London")
        #expect(flight.boardingPassData == Data([0xDE, 0xAD, 0xBE, 0xEF]))

        #expect(restored.dining.first?.status == .idea)
        #expect(restored.dining.first?.phone == "+49 89 123")
        #expect(restored.packingCategories.first?.items.first?.isPacked == true)

        let documents = try target.mainContext.fetch(FetchDescriptor<VaultDocument>())
        #expect(documents.first?.imageData == Data([1, 2, 3]))
    }

    @Test func sharedTripFileRoundTripsToAnotherDevice() throws {
        // "Send Trip to a Friend": one trip exported as .travelsteward,
        // opened on a device that has never seen it
        let source = try makeContainer()
        let trip = seedTrip(in: source.mainContext)
        try source.mainContext.save()

        let url = try BackupService.exportTrip(trip)
        #expect(url.lastPathComponent == "Munich Trip.travelsteward")

        let peeked = try BackupService.peek(at: url)
        #expect(peeked.trips.count == 1)
        #expect(peeked.trips.first?.flights.count == 1)
        #expect(peeked.vaultDocuments.isEmpty) // sharing a trip never leaks the vault

        let friend = try makeContainer()
        let summary = try BackupService.restore(from: url, context: friend.mainContext)
        #expect(summary.tripsRestored == 1)

        let restored = try #require(try friend.mainContext.fetch(FetchDescriptor<Trip>()).first)
        #expect(restored.name == "Munich Trip")
        #expect(restored.flights.first?.flightNumber == "FR1885")
        #expect(restored.dining.first?.restaurantName == "Tantris")
    }

    @Test func restoringTwiceNeverDuplicates() throws {
        let container = try makeContainer()
        _ = seedTrip(in: container.mainContext)
        try container.mainContext.save()

        let url = try BackupService.export(context: container.mainContext)
        let summary = try BackupService.restore(from: url, context: container.mainContext)

        #expect(summary.tripsRestored == 0)
        #expect(summary.tripsSkipped == 1)
        #expect(summary.documentsSkipped == 1)

        let trips = try container.mainContext.fetch(FetchDescriptor<Trip>())
        #expect(trips.count == 1)
    }
}

struct BookingShareTests {

    @Test func bookingShareLinkBecomesHotelNotFlight() async {
        // Regression: sharing a hotel from the Booking.com app produced a
        // garbage flight — URL query blobs looked like airport codes.
        let body = "Check out this hotel! https://www.booking.com/hotel/de/vier-jahreszeiten-kempinski-muenchen.html?aid=304142&label=gen173nr-1FCAEoggI46AdIM1gEaFCIAQGYAQm4ARfIAQ"
        let result = await EmailIngestionService.parseContent(subject: "Shared Content", body: body, sender: "")

        #expect(result.flights.isEmpty)
        #expect(result.hotels.count == 1)
        let name = result.hotels.first?.hotelName ?? ""
        #expect(name.localizedCaseInsensitiveContains("Kempinski"))
    }

    @Test func bookingFlightLinkGetsGuidanceNotGarbage() async {
        // Flight links carry no itinerary data — the user is pointed to
        // the email/calendar paths instead of getting a fake hotel
        let body = "My flights https://flights.booking.com/flights/LON.CITY-MUC.AIRPORT/checkout?aid=123"
        let result = await EmailIngestionService.parseContent(subject: "Shared Content", body: body, sender: "")

        #expect(result.flights.isEmpty)
        #expect(result.hotels.isEmpty)
        #expect(result.issues.contains { $0.contains("confirmation email") })
    }

    @Test func slugYieldsReadableHotelName() throws {
        let url = try #require(URL(string: "https://www.booking.com/hotel/de/vier-jahreszeiten-kempinski-muenchen.en-gb.html"))
        #expect(BookingShareImporter.nameFromSlug(of: url) == "Vier Jahreszeiten Kempinski Muenchen")
    }

    @Test func marketingTextConjuresNoFlights() {
        // Strict generic detection: unknown 3-letter words and unknown
        // two-letter+digit runs are not flights
        let result = EmailParser.parse(
            subject: "Shared Content",
            body: "Save BIG on TOP stays! Use code XY 2026 for the WOW deal.",
            sender: ""
        )
        #expect(result.flights.isEmpty)
    }

    @Test func realFlightShareStillDetected() {
        // Tightening must not break genuine generic flight content
        let result = EmailParser.parse(
            subject: "Fwd: itinerary",
            body: "LH 411 from FRA to JFK on Oct 12, 2025 at 10:30",
            sender: "friend@example.org"
        )
        #expect(result.flights.count == 1)
        #expect(result.flights.first?.flightNumber == "LH411")
    }
}

struct PDFImportTests {

    private let confirmationText = """
        Booking.com — Booking Confirmation

        Hotel Vier Jahreszeiten Kempinski
        Maximilianstrasse 17, 80539 Munich

        Check-in: Oct 12, 2025
        Check-out: Oct 18, 2025
        Confirmation: KMP884920
        """

    /// The realistic Booking.com PDF layout: unbranded property in the
    /// headline, weekday + full-month dates, dotted confirmation number
    private let realisticBookingPDF = """
        Hotel Bergblick Garni
        Bergstrasse 12, 82467 Garmisch, Germany

        YOUR RESERVATION IS CONFIRMED
        Check-in: Wednesday, 15 October 2025 (from 15:00)
        Check-out: Saturday, 18 October 2025 (until 11:00)
        Confirmation number: 3712.456.789
        PIN code: 1234
        Booked via Booking.com
        """

    @Test func pdfTextRoundTripsThroughExtractor() throws {
        // Render real text into a PDF, then extract it back
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { context in
            context.beginPage()
            confirmationText.draw(
                in: pageRect.insetBy(dx: 40, dy: 40),
                withAttributes: [.font: UIFont.systemFont(ofSize: 12)]
            )
        }

        #expect(PDFTextExtractor.isPDF(data))
        let extracted = try #require(PDFTextExtractor.text(from: data))
        #expect(extracted.contains("Kempinski"))
        #expect(extracted.contains("Check-in"))
    }

    @Test func bookingPDFTextParsesAsHotelWithDates() throws {
        let result = EmailIngestionService.parse(
            subject: "Booking Confirmation.pdf",
            body: confirmationText,
            sender: ""
        )

        #expect(result.flights.isEmpty)
        #expect(result.hotels.count == 1)
        let hotel = try #require(result.hotels.first)
        #expect(hotel.hotelName.localizedCaseInsensitiveContains("Kempinski"))
        #expect(hotel.confirmationCode == "KMP884920")

        let cal = Calendar.current
        let checkIn = try #require(hotel.checkIn)
        #expect(cal.component(.day, from: checkIn) == 12)
    }

    @Test func realisticBookingPDFParsesCompletely() throws {
        // Regression for the reported wrong-hotel/wrong-date share:
        // headline name, anchored full-month dates, dotted number
        let result = EmailIngestionService.parse(
            subject: "Confirmation.pdf",
            body: realisticBookingPDF,
            sender: ""
        )

        #expect(result.flights.isEmpty)
        let hotel = try #require(result.hotels.first)
        #expect(hotel.hotelName == "Hotel Bergblick Garni")
        #expect(hotel.confirmationCode == "3712.456.789")

        let cal = Calendar.current
        let checkIn = try #require(hotel.checkIn)
        #expect(cal.component(.day, from: checkIn) == 15)
        #expect(cal.component(.month, from: checkIn) == 10)
        #expect(cal.component(.hour, from: checkIn) == 15)

        let checkOut = try #require(hotel.checkOut)
        #expect(cal.component(.day, from: checkOut) == 18)

        #expect(result.overallConfidence >= 0.7)
    }
}

struct EmailParserFallbackTests {

    @Test func unrelatedEmailYieldsLowConfidenceAndIssue() {
        let result = EmailParser.parse(
            subject: "Hello",
            body: "Just wanted to say hi and ask about lunch next week.",
            sender: "friend@example.org"
        )

        #expect(result.flights.isEmpty)
        #expect(result.hotels.isEmpty)
        #expect(result.carRentals.isEmpty)
        #expect(result.overallConfidence <= 0.2)
        #expect(!result.issues.isEmpty)
    }

    @Test func suggestsTripNameFromArrivalCity() {
        let body = """
            Flight: Lufthansa LH411
            Date: Oct 12, 2025
            Departure: JFK (New York) at 18:30
            Arrival: MUC (Munich) at 08:15
            """
        let result = EmailParser.parse(
            subject: "Flight confirmation",
            body: body,
            sender: "noreply@lufthansa.com"
        )

        #expect(!result.suggestedTripName.isEmpty)
        #expect(result.suggestedTripName != "New Trip")
    }
}
