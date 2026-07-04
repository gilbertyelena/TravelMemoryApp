//
//  Destination.swift
//  TravelMemory
//
//  Created by Yelena Gilbert on 28/04/2026.
//

import Foundation
import SwiftData
import CoreLocation

// MARK: - Destination Model

@Model
final class Destination {
    var id: UUID = UUID()
    var city: String
    var country: String
    var dateFrom: Date
    var dateTo: Date
    var latitude: Double
    var longitude: Double
    var coverPhotoData: Data?
    var hotelName: String
    var hotelLink: String
    var notes: String
    
    @Relationship(deleteRule: .cascade) var memories: [Memory] = []
    @Relationship(deleteRule: .cascade) var photos: [Photo] = []
    
    init(
        city: String = "",
        country: String = "",
        dateFrom: Date = .now,
        dateTo: Date = .now,
        latitude: Double = 0.0,
        longitude: Double = 0.0,
        coverPhotoData: Data? = nil,
        hotelName: String = "",
        hotelLink: String = "",
        notes: String = ""
    ) {
        self.city = city
        self.country = country
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.latitude = latitude
        self.longitude = longitude
        self.coverPhotoData = coverPhotoData
        self.hotelName = hotelName
        self.hotelLink = hotelLink
        self.notes = notes
    }
    
    var displayName: String {
        if city.isEmpty && country.isEmpty { return "New Destination" }
        if city.isEmpty { return country }
        if country.isEmpty { return city }
        return "\(city), \(country)"
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    var tripDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day]
        formatter.unitsStyle = .short
        let days = Calendar.current.dateComponents([.day], from: dateFrom, to: dateTo).day ?? 0
        return days == 1 ? "1 day" : "\(days) days"
    }
    
    var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: dateFrom)) – \(formatter.string(from: dateTo))"
    }
}

// MARK: - Memory Model

@Model
final class Memory {
    var title: String
    var details: String
    var category: String  // food, performance, activity, other
    var externalLink: String
    var date: Date
    
    init(
        title: String = "",
        details: String = "",
        category: String = "other",
        externalLink: String = "",
        date: Date = .now
    ) {
        self.title = title
        self.details = details
        self.category = category
        self.externalLink = externalLink
        self.date = date
    }
    
    var categoryIcon: String {
        switch category {
        case "food": return "fork.knife"
        case "performance": return "theatermasks"
        case "activity": return "figure.skiing.downhill"
        case "nature": return "leaf"
        case "shopping": return "bag"
        case "culture": return "building.columns"
        default: return "star"
        }
    }
    
    static let categories = [
        "food", "performance", "activity", "nature", "shopping", "culture", "other"
    ]
    
    static func categoryLabel(_ cat: String) -> String {
        switch cat {
        case "food": return "Food & Drink"
        case "performance": return "Performance"
        case "activity": return "Activity"
        case "nature": return "Nature"
        case "shopping": return "Shopping"
        case "culture": return "Culture"
        default: return "Other"
        }
    }
}

// MARK: - Photo Model

@Model
final class Photo {
    @Attribute(.externalStorage) var imageData: Data?
    var caption: String
    var dateTaken: Date
    
    init(imageData: Data? = nil, caption: String = "", dateTaken: Date = .now) {
        self.imageData = imageData
        self.caption = caption
        self.dateTaken = dateTaken
    }
}
