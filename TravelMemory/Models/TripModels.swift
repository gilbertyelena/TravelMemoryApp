//
//  TripModels.swift
//  TravelMemory
//
//  SwiftData models for the Travel Steward itinerary system.
//  These power the Trip Planning timeline, Live Itinerary,
//  Secure Vault, and Inbox Review screens.
//

import Foundation
import SwiftData

// MARK: - Trip (Root Container)

@Model
final class Trip: Hashable {
    static func == (lhs: Trip, rhs: Trip) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    var id: UUID = UUID()
    var name: String = ""
    var destination: String = ""
    var startDate: Date = Date.now
    var endDate: Date = Date.now
    var statusRaw: String = "" // "planning", "live", "completed"
    var createdAt: Date = Date()
    /// IANA zone of the destination (geocoded); itinerary times display
    /// in this zone so the schedule matches local clocks when abroad
    var timeZoneID: String = ""
    
    // CloudKit demands every relationship be optional — the stored
    // arrays are, with originalName preserving existing on-disk data.
    // The app only ever touches the non-optional accessors below.
    @Relationship(deleteRule: .cascade, originalName: "flights") private var flightsStorage: [FlightSegment]? = []
    @Relationship(deleteRule: .cascade, originalName: "hotels") private var hotelsStorage: [HotelBooking]? = []
    @Relationship(deleteRule: .cascade, originalName: "carRentals") private var carRentalsStorage: [CarRentalBooking]? = []
    @Relationship(deleteRule: .cascade, originalName: "dining") private var diningStorage: [DiningReservation]? = []
    @Relationship(deleteRule: .cascade, originalName: "activities") private var activitiesStorage: [TripActivity]? = []
    @Relationship(deleteRule: .cascade, originalName: "parsedEmails") private var parsedEmailsStorage: [ParsedEmail]? = []
    @Relationship(deleteRule: .cascade, originalName: "packingCategories") private var packingCategoriesStorage: [PackingCategoryModel]? = []

    var flights: [FlightSegment] {
        get { flightsStorage ?? [] }
        set { flightsStorage = newValue }
    }
    var hotels: [HotelBooking] {
        get { hotelsStorage ?? [] }
        set { hotelsStorage = newValue }
    }
    var carRentals: [CarRentalBooking] {
        get { carRentalsStorage ?? [] }
        set { carRentalsStorage = newValue }
    }
    var dining: [DiningReservation] {
        get { diningStorage ?? [] }
        set { diningStorage = newValue }
    }
    var activities: [TripActivity] {
        get { activitiesStorage ?? [] }
        set { activitiesStorage = newValue }
    }
    var parsedEmails: [ParsedEmail] {
        get { parsedEmailsStorage ?? [] }
        set { parsedEmailsStorage = newValue }
    }
    var packingCategories: [PackingCategoryModel] {
        get { packingCategoriesStorage ?? [] }
        set { packingCategoriesStorage = newValue }
    }
    
    init(
        name: String = "",
        destination: String = "",
        startDate: Date = .now,
        endDate: Date = .now,
        statusRaw: String = "planning"
    ) {
        self.name = name
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.statusRaw = statusRaw
    }
    
    var status: TripStatus {
        get { TripStatus(rawValue: statusRaw) ?? .planning }
        set { statusRaw = newValue.rawValue }
    }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneID) ?? .current
    }

    /// Calendar in the destination's zone, for day grouping
    var calendar: Calendar {
        var cal = Calendar.current
        cal.timeZone = timeZone
        return cal
    }
    
    var durationDays: Int {
        Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
    }
    
    var dateRangeText: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return "\(fmt.string(from: startDate)) - \(fmt.string(from: endDate))"
    }
    
    /// All itinerary items sorted by date
    var timelineItems: [any ItineraryItem] {
        var items: [any ItineraryItem] = []
        items.append(contentsOf: flights)
        items.append(contentsOf: hotels)
        items.append(contentsOf: carRentals)
        items.append(contentsOf: dining)
        items.append(contentsOf: activities)
        return items.sorted { $0.eventDate < $1.eventDate }
    }
    
    /// Count of items needing review
    var pendingReviewCount: Int {
        parsedEmails.filter { $0.status == .needsReview }.count
    }

    /// Costs summed per currency ("" groups with the device currency symbol)
    var costTotals: [(currency: String, total: Double)] {
        var totals: [String: Double] = [:]
        for item in timelineItems where item.cost > 0 {
            totals[item.currencyCode.uppercased(), default: 0] += item.cost
        }
        return totals.sorted { $0.key < $1.key }.map { (currency: $0.key, total: $0.value) }
    }

    /// "£450 + €230" style summary, empty when no costs are recorded
    var budgetText: String {
        costTotals.map { entry in
            let symbol = Self.currencySymbol(for: entry.currency)
            let amount = entry.total.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", entry.total)
                : String(format: "%.2f", entry.total)
            return "\(symbol)\(amount)"
        }.joined(separator: " + ")
    }

    static func currencySymbol(for code: String) -> String {
        switch code.uppercased() {
        case "": return Locale.current.currencySymbol ?? "¤"
        case "GBP": return "£"
        case "EUR": return "€"
        case "USD": return "$"
        case "JPY": return "¥"
        case "CHF": return "CHF "
        default: return code.uppercased() + " "
        }
    }
}

enum TripStatus: String, Codable, CaseIterable {
    case planning, live, completed
}

// MARK: - Item Status (idea → planned → booked)

/// Lifecycle of an itinerary item, so the app can hold plans and
/// candidates ("maybe dinner here?") — not just confirmed bookings.
enum ItineraryItemStatus: String, Codable, CaseIterable {
    case idea, planned, booked

    var label: String {
        switch self {
        case .idea: return "Idea"
        case .planned: return "Planned"
        case .booked: return "Booked"
        }
    }

    var icon: String {
        switch self {
        case .idea: return "lightbulb"
        case .planned: return "calendar.badge.clock"
        case .booked: return "checkmark.seal.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .idea: return "#8B91A0"
        case .planned: return "#FFB868"
        case .booked: return "#38EF7D"
        }
    }
}

// MARK: - Itinerary Item Protocol

protocol ItineraryItem: AnyObject {
    var eventDate: Date { get }
    var itemType: ItineraryItemType { get }
    var confidence: Double { get }
    var confirmationCode: String { get }
    var statusRaw: String { get set }
    var cost: Double { get set }
    var currencyCode: String { get set }
    /// IANA zone the event happens in ("" = inherit the trip's zone)
    var timeZoneID: String { get set }
}

extension ItineraryItem {
    var status: ItineraryItemStatus {
        get { ItineraryItemStatus(rawValue: statusRaw) ?? .booked }
        set { statusRaw = newValue.rawValue }
    }

    /// The zone this event's times should display in
    func eventTimeZone(fallback: TimeZone) -> TimeZone {
        TimeZone(identifier: timeZoneID) ?? fallback
    }
}

enum ItineraryItemType: String, Codable {
    case flight, hotel, carRental, dining, activity
    
    var icon: String {
        switch self {
        case .flight: return "airplane.departure"
        case .hotel: return "bed.double"
        case .carRental: return "car"
        case .dining: return "fork.knife"
        case .activity: return "figure.walk"
        }
    }
    
    var label: String {
        switch self {
        case .flight: return "FLIGHT"
        case .hotel: return "LODGING"
        case .carRental: return "CAR RENTAL"
        case .dining: return "DINING"
        case .activity: return "ACTIVITY"
        }
    }
}

// MARK: - Flight Segment

@Model
final class FlightSegment: ItineraryItem {
    var id: UUID = UUID()
    var airline: String = ""
    var flightNumber: String = ""
    var departureAirport: String = ""
    var departureCity: String = ""
    var arrivalAirport: String = ""
    var arrivalCity: String = ""
    var departureTime: Date = Date.now
    var arrivalTime: Date = Date.now
    var gate: String = ""
    var seat: String = ""
    var terminal: String = ""
    var confirmationCode: String = ""
    var confidence: Double = 0
    // Item lifecycle + budget (defaults keep SwiftData migration lightweight)
    var statusRaw: String = ItineraryItemStatus.booked.rawValue
    var cost: Double = 0
    var currencyCode: String = ""
    var timeZoneID: String = "" // departure zone
    var arrivalTimeZoneID: String = ""
    /// Boarding pass screenshot/photo, shown full-screen at the gate
    @Attribute(.externalStorage) var boardingPassData: Data? = nil
    
    var trip: Trip?
    
    init(
        airline: String = "",
        flightNumber: String = "",
        departureAirport: String = "",
        departureCity: String = "",
        arrivalAirport: String = "",
        arrivalCity: String = "",
        departureTime: Date = .now,
        arrivalTime: Date = .now,
        gate: String = "",
        seat: String = "",
        terminal: String = "",
        confirmationCode: String = "",
        confidence: Double = 1.0
    ) {
        self.airline = airline
        self.flightNumber = flightNumber
        self.departureAirport = departureAirport
        self.departureCity = departureCity
        self.arrivalAirport = arrivalAirport
        self.arrivalCity = arrivalCity
        self.departureTime = departureTime
        self.arrivalTime = arrivalTime
        self.gate = gate
        self.seat = seat
        self.terminal = terminal
        self.confirmationCode = confirmationCode
        self.confidence = confidence
    }
    
    var eventDate: Date { departureTime }
    var itemType: ItineraryItemType { .flight }
    
    var routeText: String {
        "\(departureAirport) → \(arrivalAirport)"
    }
    
    var airlineAndFlight: String {
        "\(airline) \(flightNumber)"
    }
}

// MARK: - Hotel Booking

@Model
final class HotelBooking: ItineraryItem {
    var id: UUID = UUID()
    var hotelName: String = ""
    var address: String = ""
    var checkInDate: Date = Date.now
    var checkOutDate: Date = Date.now
    var confirmationCode: String = ""
    var roomType: String = ""
    var confidence: Double = 0
    // Item lifecycle + budget (defaults keep SwiftData migration lightweight)
    var statusRaw: String = ItineraryItemStatus.booked.rawValue
    var cost: Double = 0
    var currencyCode: String = ""
    var timeZoneID: String = ""
    
    var trip: Trip?
    
    init(
        hotelName: String = "",
        address: String = "",
        checkInDate: Date = .now,
        checkOutDate: Date = .now,
        confirmationCode: String = "",
        roomType: String = "",
        confidence: Double = 1.0
    ) {
        self.hotelName = hotelName
        self.address = address
        self.checkInDate = checkInDate
        self.checkOutDate = checkOutDate
        self.confirmationCode = confirmationCode
        self.roomType = roomType
        self.confidence = confidence
    }
    
    var eventDate: Date { checkInDate }
    var itemType: ItineraryItemType { .hotel }
    
    var nightsCount: Int {
        Calendar.current.dateComponents([.day], from: checkInDate, to: checkOutDate).day ?? 0
    }
}

// MARK: - Car Rental Booking

@Model
final class CarRentalBooking: ItineraryItem {
    var id: UUID = UUID()
    var company: String = ""
    var vehicleType: String = ""
    var pickupTime: Date = Date.now
    var dropoffTime: Date = Date.now
    var pickupLocation: String = ""
    var dropoffLocation: String = ""
    var confirmationCode: String = ""
    var isPrepaid: Bool = false
    var confidence: Double = 0
    // Item lifecycle + budget (defaults keep SwiftData migration lightweight)
    var statusRaw: String = ItineraryItemStatus.booked.rawValue
    var cost: Double = 0
    var currencyCode: String = ""
    var timeZoneID: String = ""
    
    var trip: Trip?
    
    init(
        company: String = "",
        vehicleType: String = "",
        pickupTime: Date = .now,
        dropoffTime: Date = .now,
        pickupLocation: String = "",
        dropoffLocation: String = "",
        confirmationCode: String = "",
        isPrepaid: Bool = false,
        confidence: Double = 1.0
    ) {
        self.company = company
        self.vehicleType = vehicleType
        self.pickupTime = pickupTime
        self.dropoffTime = dropoffTime
        self.pickupLocation = pickupLocation
        self.dropoffLocation = dropoffLocation
        self.confirmationCode = confirmationCode
        self.isPrepaid = isPrepaid
        self.confidence = confidence
    }
    
    var eventDate: Date { pickupTime }
    var itemType: ItineraryItemType { .carRental }
}

// MARK: - Dining Reservation

@Model
final class DiningReservation: ItineraryItem {
    var id: UUID = UUID()
    var restaurantName: String = ""
    var address: String = ""
    var reservationTime: Date = Date.now
    var partySize: Int = 0
    var confirmationCode: String = ""
    var notes: String = ""
    // Contact details captured from map search, for one-tap booking handoff
    var phone: String = ""
    var websiteURL: String = ""
    var confidence: Double = 0
    // Item lifecycle + budget (defaults keep SwiftData migration lightweight)
    var statusRaw: String = ItineraryItemStatus.booked.rawValue
    var cost: Double = 0
    var currencyCode: String = ""
    var timeZoneID: String = ""
    
    var trip: Trip?
    
    init(
        restaurantName: String = "",
        address: String = "",
        reservationTime: Date = .now,
        partySize: Int = 2,
        confirmationCode: String = "",
        notes: String = "",
        phone: String = "",
        websiteURL: String = "",
        confidence: Double = 1.0
    ) {
        self.restaurantName = restaurantName
        self.address = address
        self.reservationTime = reservationTime
        self.partySize = partySize
        self.confirmationCode = confirmationCode
        self.notes = notes
        self.phone = phone
        self.websiteURL = websiteURL
        self.confidence = confidence
    }
    
    var eventDate: Date { reservationTime }
    var itemType: ItineraryItemType { .dining }
}

// MARK: - Trip Activity

enum ActivityCategory: String, CaseIterable, Codable {
    case water, adventure, cultural, wellness, entertainment, other
    
    var label: String {
        switch self {
        case .water: return "Water"
        case .adventure: return "Adventure"
        case .cultural: return "Cultural"
        case .wellness: return "Wellness"
        case .entertainment: return "Entertainment"
        case .other: return "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .water: return "water.waves"
        case .adventure: return "figure.hiking"
        case .cultural: return "building.columns"
        case .wellness: return "leaf"
        case .entertainment: return "theatermasks"
        case .other: return "star"
        }
    }
    
    var color: String {
        switch self {
        case .water: return "#0A84FF"
        case .adventure: return "#38EF7D"
        case .cultural: return "#FFB868"
        case .wellness: return "#BF5AF2"
        case .entertainment: return "#FF6B6B"
        case .other: return "#8B91A0"
        }
    }
}

@Model
final class TripActivity: ItineraryItem {
    var id: UUID = UUID()
    var activityName: String = ""
    var provider: String = ""
    var location: String = ""
    var categoryRaw: String = ""
    var startTime: Date = Date.now
    var endTime: Date = Date.now
    var confirmationCode: String = ""
    var notes: String = ""
    var priceInfo: String = ""
    var confidence: Double = 0
    // Item lifecycle + budget (defaults keep SwiftData migration lightweight)
    var statusRaw: String = ItineraryItemStatus.booked.rawValue
    var cost: Double = 0
    var currencyCode: String = ""
    var timeZoneID: String = ""
    
    var trip: Trip?
    
    init(
        activityName: String = "",
        provider: String = "",
        location: String = "",
        categoryRaw: String = "other",
        startTime: Date = .now,
        endTime: Date = .now,
        confirmationCode: String = "",
        notes: String = "",
        priceInfo: String = "",
        confidence: Double = 1.0
    ) {
        self.activityName = activityName
        self.provider = provider
        self.location = location
        self.categoryRaw = categoryRaw
        self.startTime = startTime
        self.endTime = endTime
        self.confirmationCode = confirmationCode
        self.notes = notes
        self.priceInfo = priceInfo
        self.confidence = confidence
    }
    
    var category: ActivityCategory {
        get { ActivityCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
    
    var eventDate: Date { startTime }
    var itemType: ItineraryItemType { .activity }
}

// MARK: - Parsed Email

@Model
final class ParsedEmail {
    var id: UUID = UUID()
    var subject: String = ""
    var senderEmail: String = ""
    var rawBody: String = ""
    var receivedAt: Date = Date.now
    var parsedAt: Date = Date()
    var statusRaw: String = "" // "pending", "needsReview", "accepted", "rejected"
    var overallConfidence: Double = 0
    var issues: [String] = [] // JSON-encoded array of issue descriptions
    
    var trip: Trip?
    
    init(
        subject: String = "",
        senderEmail: String = "",
        rawBody: String = "",
        receivedAt: Date = .now,
        statusRaw: String = "pending",
        overallConfidence: Double = 0.0,
        issues: [String] = []
    ) {
        self.subject = subject
        self.senderEmail = senderEmail
        self.rawBody = rawBody
        self.receivedAt = receivedAt
        self.statusRaw = statusRaw
        self.overallConfidence = overallConfidence
        self.issues = issues
    }
    
    var status: ParseStatus {
        get { ParseStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}

enum ParseStatus: String, Codable {
    case pending, needsReview, accepted, rejected
}
