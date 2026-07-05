//
//  TravelMemoryTests.swift
//  TravelMemoryTests
//
//  Fixture-based tests for the email parser — the most failure-prone
//  and most testable component in the app.
//

import Foundation
import Testing
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
