//
//  BackupService.swift
//  TravelMemory
//
//  Full-database backup to a single JSON file and back. This is the
//  escape hatch: migrate to a new phone, survive a signing-team switch
//  (which forces reinstall), or just keep an off-device copy of every
//  trip and vault document.
//
//  Restore merges by id — records that already exist are skipped, so
//  restoring twice never duplicates anything.
//

import Foundation
import SwiftData

// MARK: - Archive Format (versioned, all fields explicit)

struct BackupArchive: Codable {
    var version: Int = 1
    var exportedAt: Date = Date()
    var trips: [TripBackup] = []
    var vaultDocuments: [VaultDocumentBackup] = []

    struct TripBackup: Codable {
        var id: UUID
        var name: String
        var destination: String
        var startDate: Date
        var endDate: Date
        var statusRaw: String
        var createdAt: Date
        var timeZoneID: String
        var flights: [FlightBackup] = []
        var hotels: [HotelBackup] = []
        var carRentals: [CarBackup] = []
        var dining: [DiningBackup] = []
        var activities: [ActivityBackup] = []
        var parsedEmails: [ParsedEmailBackup] = []
        var packingCategories: [PackingCategoryBackup] = []
    }

    struct FlightBackup: Codable {
        var id: UUID
        var airline: String
        var flightNumber: String
        var departureAirport: String
        var departureCity: String
        var arrivalAirport: String
        var arrivalCity: String
        var departureTime: Date
        var arrivalTime: Date
        var gate: String
        var seat: String
        var terminal: String
        var confirmationCode: String
        var confidence: Double
        var statusRaw: String
        var cost: Double
        var currencyCode: String
        var timeZoneID: String
        var arrivalTimeZoneID: String
        var boardingPassData: Data?
    }

    struct HotelBackup: Codable {
        var id: UUID
        var hotelName: String
        var address: String
        var checkInDate: Date
        var checkOutDate: Date
        var confirmationCode: String
        var roomType: String
        var confidence: Double
        var statusRaw: String
        var cost: Double
        var currencyCode: String
        var timeZoneID: String
    }

    struct CarBackup: Codable {
        var id: UUID
        var company: String
        var vehicleType: String
        var pickupTime: Date
        var dropoffTime: Date
        var pickupLocation: String
        var dropoffLocation: String
        var confirmationCode: String
        var isPrepaid: Bool
        var confidence: Double
        var statusRaw: String
        var cost: Double
        var currencyCode: String
        var timeZoneID: String
    }

    struct DiningBackup: Codable {
        var id: UUID
        var restaurantName: String
        var address: String
        var reservationTime: Date
        var partySize: Int
        var confirmationCode: String
        var notes: String
        var phone: String
        var websiteURL: String
        var confidence: Double
        var statusRaw: String
        var cost: Double
        var currencyCode: String
        var timeZoneID: String
    }

    struct ActivityBackup: Codable {
        var id: UUID
        var activityName: String
        var provider: String
        var location: String
        var categoryRaw: String
        var startTime: Date
        var endTime: Date
        var confirmationCode: String
        var notes: String
        var priceInfo: String
        var confidence: Double
        var statusRaw: String
        var cost: Double
        var currencyCode: String
        var timeZoneID: String
    }

    struct ParsedEmailBackup: Codable {
        var id: UUID
        var subject: String
        var senderEmail: String
        var rawBody: String
        var receivedAt: Date
        var parsedAt: Date
        var statusRaw: String
        var overallConfidence: Double
        var issues: [String]
    }

    struct PackingCategoryBackup: Codable {
        var id: UUID
        var name: String
        var icon: String
        var colorHex: String
        var sortOrder: Int
        var items: [PackingItemBackup] = []
    }

    struct PackingItemBackup: Codable {
        var id: UUID
        var name: String
        var isPacked: Bool
        var quantity: Int
        var sortOrder: Int
    }

    struct VaultDocumentBackup: Codable {
        var id: UUID
        var title: String
        var categoryRaw: String
        var imageData: Data?
        var notes: String
        var createdAt: Date
    }
}

struct RestoreSummary {
    var tripsRestored = 0
    var tripsSkipped = 0
    var documentsRestored = 0
    var documentsSkipped = 0

    var text: String {
        var parts: [String] = []
        parts.append("\(tripsRestored) trip\(tripsRestored == 1 ? "" : "s") restored")
        if tripsSkipped > 0 { parts.append("\(tripsSkipped) already present") }
        parts.append("\(documentsRestored) document\(documentsRestored == 1 ? "" : "s") restored")
        if documentsSkipped > 0 { parts.append("\(documentsSkipped) already present") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Service

@MainActor
struct BackupService {

    enum BackupError: LocalizedError {
        case unreadableFile
        case incompatibleVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unreadableFile:
                return "That file isn't a Travel Steward backup."
            case .incompatibleVersion(let version):
                return "This backup (format v\(version)) needs a newer version of the app."
            }
        }
    }

    // MARK: Export

    /// Serializes the whole database to a JSON file and returns its URL.
    static func export(context: ModelContext) throws -> URL {
        var archive = BackupArchive()

        let trips = try context.fetch(FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startDate)]))
        archive.trips = trips.map { backup(of: $0) }

        let documents = try context.fetch(FetchDescriptor<VaultDocument>())
        archive.vaultDocuments = documents.map {
            BackupArchive.VaultDocumentBackup(
                id: $0.id, title: $0.title, categoryRaw: $0.categoryRaw,
                imageData: $0.imageData, notes: $0.notes, createdAt: $0.createdAt
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)

        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TravelSteward-Backup-\(dayFmt.string(from: Date())).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: Restore

    /// Imports an archive, skipping trips/documents whose id already
    /// exists. Safe to run repeatedly.
    @discardableResult
    static func restore(from url: URL, context: ModelContext) throws -> RestoreSummary {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            throw BackupError.unreadableFile
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(BackupArchive.self, from: data) else {
            throw BackupError.unreadableFile
        }
        guard archive.version <= 1 else {
            throw BackupError.incompatibleVersion(archive.version)
        }

        var summary = RestoreSummary()

        let existingTripIDs = Set((try? context.fetch(FetchDescriptor<Trip>()))?.map(\.id) ?? [])
        for tripBackup in archive.trips {
            if existingTripIDs.contains(tripBackup.id) {
                summary.tripsSkipped += 1
                continue
            }
            let trip = instantiate(tripBackup)
            context.insert(trip)
            summary.tripsRestored += 1
        }

        let existingDocumentIDs = Set((try? context.fetch(FetchDescriptor<VaultDocument>()))?.map(\.id) ?? [])
        for documentBackup in archive.vaultDocuments {
            if existingDocumentIDs.contains(documentBackup.id) {
                summary.documentsSkipped += 1
                continue
            }
            let document = VaultDocument(
                title: documentBackup.title,
                categoryRaw: documentBackup.categoryRaw,
                imageData: documentBackup.imageData,
                notes: documentBackup.notes
            )
            document.id = documentBackup.id
            document.createdAt = documentBackup.createdAt
            context.insert(document)
            summary.documentsRestored += 1
        }

        try context.save()
        return summary
    }

    // MARK: - Model → DTO

    private static func backup(of trip: Trip) -> BackupArchive.TripBackup {
        var backup = BackupArchive.TripBackup(
            id: trip.id, name: trip.name, destination: trip.destination,
            startDate: trip.startDate, endDate: trip.endDate,
            statusRaw: trip.statusRaw, createdAt: trip.createdAt,
            timeZoneID: trip.timeZoneID
        )
        backup.flights = trip.flights.map { f in
            BackupArchive.FlightBackup(
                id: f.id, airline: f.airline, flightNumber: f.flightNumber,
                departureAirport: f.departureAirport, departureCity: f.departureCity,
                arrivalAirport: f.arrivalAirport, arrivalCity: f.arrivalCity,
                departureTime: f.departureTime, arrivalTime: f.arrivalTime,
                gate: f.gate, seat: f.seat, terminal: f.terminal,
                confirmationCode: f.confirmationCode, confidence: f.confidence,
                statusRaw: f.statusRaw, cost: f.cost, currencyCode: f.currencyCode,
                timeZoneID: f.timeZoneID, arrivalTimeZoneID: f.arrivalTimeZoneID,
                boardingPassData: f.boardingPassData
            )
        }
        backup.hotels = trip.hotels.map { h in
            BackupArchive.HotelBackup(
                id: h.id, hotelName: h.hotelName, address: h.address,
                checkInDate: h.checkInDate, checkOutDate: h.checkOutDate,
                confirmationCode: h.confirmationCode, roomType: h.roomType,
                confidence: h.confidence, statusRaw: h.statusRaw,
                cost: h.cost, currencyCode: h.currencyCode, timeZoneID: h.timeZoneID
            )
        }
        backup.carRentals = trip.carRentals.map { c in
            BackupArchive.CarBackup(
                id: c.id, company: c.company, vehicleType: c.vehicleType,
                pickupTime: c.pickupTime, dropoffTime: c.dropoffTime,
                pickupLocation: c.pickupLocation, dropoffLocation: c.dropoffLocation,
                confirmationCode: c.confirmationCode, isPrepaid: c.isPrepaid,
                confidence: c.confidence, statusRaw: c.statusRaw,
                cost: c.cost, currencyCode: c.currencyCode, timeZoneID: c.timeZoneID
            )
        }
        backup.dining = trip.dining.map { d in
            BackupArchive.DiningBackup(
                id: d.id, restaurantName: d.restaurantName, address: d.address,
                reservationTime: d.reservationTime, partySize: d.partySize,
                confirmationCode: d.confirmationCode, notes: d.notes,
                phone: d.phone, websiteURL: d.websiteURL,
                confidence: d.confidence, statusRaw: d.statusRaw,
                cost: d.cost, currencyCode: d.currencyCode, timeZoneID: d.timeZoneID
            )
        }
        backup.activities = trip.activities.map { a in
            BackupArchive.ActivityBackup(
                id: a.id, activityName: a.activityName, provider: a.provider,
                location: a.location, categoryRaw: a.categoryRaw,
                startTime: a.startTime, endTime: a.endTime,
                confirmationCode: a.confirmationCode, notes: a.notes,
                priceInfo: a.priceInfo, confidence: a.confidence,
                statusRaw: a.statusRaw, cost: a.cost, currencyCode: a.currencyCode,
                timeZoneID: a.timeZoneID
            )
        }
        backup.parsedEmails = trip.parsedEmails.map { e in
            BackupArchive.ParsedEmailBackup(
                id: e.id, subject: e.subject, senderEmail: e.senderEmail,
                rawBody: e.rawBody, receivedAt: e.receivedAt, parsedAt: e.parsedAt,
                statusRaw: e.statusRaw, overallConfidence: e.overallConfidence,
                issues: e.issues
            )
        }
        backup.packingCategories = trip.packingCategories.map { category in
            var categoryBackup = BackupArchive.PackingCategoryBackup(
                id: category.id, name: category.name, icon: category.icon,
                colorHex: category.colorHex, sortOrder: category.sortOrder
            )
            categoryBackup.items = category.items.map { item in
                BackupArchive.PackingItemBackup(
                    id: item.id, name: item.name, isPacked: item.isPacked,
                    quantity: item.quantity, sortOrder: item.sortOrder
                )
            }
            return categoryBackup
        }
        return backup
    }

    // MARK: - DTO → Model

    private static func instantiate(_ backup: BackupArchive.TripBackup) -> Trip {
        let trip = Trip(
            name: backup.name, destination: backup.destination,
            startDate: backup.startDate, endDate: backup.endDate,
            statusRaw: backup.statusRaw
        )
        trip.id = backup.id
        trip.createdAt = backup.createdAt
        trip.timeZoneID = backup.timeZoneID

        for f in backup.flights {
            let flight = FlightSegment(
                airline: f.airline, flightNumber: f.flightNumber,
                departureAirport: f.departureAirport, departureCity: f.departureCity,
                arrivalAirport: f.arrivalAirport, arrivalCity: f.arrivalCity,
                departureTime: f.departureTime, arrivalTime: f.arrivalTime,
                gate: f.gate, seat: f.seat, terminal: f.terminal,
                confirmationCode: f.confirmationCode, confidence: f.confidence
            )
            flight.id = f.id
            flight.statusRaw = f.statusRaw
            flight.cost = f.cost
            flight.currencyCode = f.currencyCode
            flight.timeZoneID = f.timeZoneID
            flight.arrivalTimeZoneID = f.arrivalTimeZoneID
            flight.boardingPassData = f.boardingPassData
            trip.flights.append(flight)
        }
        for h in backup.hotels {
            let hotel = HotelBooking(
                hotelName: h.hotelName, address: h.address,
                checkInDate: h.checkInDate, checkOutDate: h.checkOutDate,
                confirmationCode: h.confirmationCode, roomType: h.roomType,
                confidence: h.confidence
            )
            hotel.id = h.id
            hotel.statusRaw = h.statusRaw
            hotel.cost = h.cost
            hotel.currencyCode = h.currencyCode
            hotel.timeZoneID = h.timeZoneID
            trip.hotels.append(hotel)
        }
        for c in backup.carRentals {
            let car = CarRentalBooking(
                company: c.company, vehicleType: c.vehicleType,
                pickupTime: c.pickupTime, dropoffTime: c.dropoffTime,
                pickupLocation: c.pickupLocation, dropoffLocation: c.dropoffLocation,
                confirmationCode: c.confirmationCode, isPrepaid: c.isPrepaid,
                confidence: c.confidence
            )
            car.id = c.id
            car.statusRaw = c.statusRaw
            car.cost = c.cost
            car.currencyCode = c.currencyCode
            car.timeZoneID = c.timeZoneID
            trip.carRentals.append(car)
        }
        for d in backup.dining {
            let dining = DiningReservation(
                restaurantName: d.restaurantName, address: d.address,
                reservationTime: d.reservationTime, partySize: d.partySize,
                confirmationCode: d.confirmationCode, notes: d.notes,
                phone: d.phone, websiteURL: d.websiteURL,
                confidence: d.confidence
            )
            dining.id = d.id
            dining.statusRaw = d.statusRaw
            dining.cost = d.cost
            dining.currencyCode = d.currencyCode
            dining.timeZoneID = d.timeZoneID
            trip.dining.append(dining)
        }
        for a in backup.activities {
            let activity = TripActivity(
                activityName: a.activityName, provider: a.provider,
                location: a.location, categoryRaw: a.categoryRaw,
                startTime: a.startTime, endTime: a.endTime,
                confirmationCode: a.confirmationCode, notes: a.notes,
                priceInfo: a.priceInfo, confidence: a.confidence
            )
            activity.id = a.id
            activity.statusRaw = a.statusRaw
            activity.cost = a.cost
            activity.currencyCode = a.currencyCode
            activity.timeZoneID = a.timeZoneID
            trip.activities.append(activity)
        }
        for e in backup.parsedEmails {
            let email = ParsedEmail(
                subject: e.subject, senderEmail: e.senderEmail, rawBody: e.rawBody,
                receivedAt: e.receivedAt, statusRaw: e.statusRaw,
                overallConfidence: e.overallConfidence, issues: e.issues
            )
            email.id = e.id
            email.parsedAt = e.parsedAt
            trip.parsedEmails.append(email)
        }
        for categoryBackup in backup.packingCategories {
            let category = PackingCategoryModel(
                name: categoryBackup.name, icon: categoryBackup.icon,
                colorHex: categoryBackup.colorHex, sortOrder: categoryBackup.sortOrder
            )
            category.id = categoryBackup.id
            for itemBackup in categoryBackup.items {
                let item = PackingItemModel(
                    name: itemBackup.name, isPacked: itemBackup.isPacked,
                    quantity: itemBackup.quantity, sortOrder: itemBackup.sortOrder
                )
                item.id = itemBackup.id
                category.items.append(item)
            }
            trip.packingCategories.append(category)
        }
        return trip
    }
}
