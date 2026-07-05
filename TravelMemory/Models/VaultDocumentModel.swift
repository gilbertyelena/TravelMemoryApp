//
//  VaultDocumentModel.swift
//  TravelMemory
//
//  Model for documents stored in the Secure Vault.
//

import Foundation
import SwiftData

@Model
final class VaultDocument {
    var id: UUID = UUID()
    var title: String = ""
    var categoryRaw: String = ""  // "passport", "visa", "insurance", "boarding", "other"
    @Attribute(.externalStorage) var imageData: Data?
    var notes: String = ""
    var createdAt: Date = Date()
    
    init(
        title: String = "",
        categoryRaw: String = "other",
        imageData: Data? = nil,
        notes: String = ""
    ) {
        self.title = title
        self.categoryRaw = categoryRaw
        self.imageData = imageData
        self.notes = notes
    }
    
    var category: VaultCategory {
        get { VaultCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}

enum VaultCategory: String, CaseIterable, Codable {
    case passport, visa, insurance, boarding, other
    
    var label: String {
        switch self {
        case .passport: return "Passport"
        case .visa: return "Visa"
        case .insurance: return "Insurance"
        case .boarding: return "Boarding Pass"
        case .other: return "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .passport: return "book.closed.fill"
        case .visa: return "checkmark.seal.fill"
        case .insurance: return "cross.case.fill"
        case .boarding: return "airplane"
        case .other: return "doc.fill"
        }
    }
    
    var color: String {
        switch self {
        case .passport: return "#667EEA"
        case .visa: return "#11998E"
        case .insurance: return "#EF4444"
        case .boarding: return "#0A84FF"
        case .other: return "#8B91A0"
        }
    }
}
