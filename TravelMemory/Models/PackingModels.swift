//
//  PackingModels.swift
//  TravelMemory
//
//  Persistent SwiftData models for packing lists.
//  Each trip can have its own packing categories and items.
//

import Foundation
import SwiftData

// MARK: - Packing Category

@Model
final class PackingCategoryModel {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = ""
    var colorHex: String = ""  // Store color as hex for persistence
    var sortOrder: Int = 0
    
    @Relationship(deleteRule: .cascade) var items: [PackingItemModel] = []
    var trip: Trip?
    
    init(
        name: String = "",
        icon: String = "folder.fill",
        colorHex: String = "#0A85FF",
        sortOrder: Int = 0
    ) {
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.sortOrder = sortOrder
    }
    
    var packedCount: Int {
        items.filter(\.isPacked).count
    }
    
    var totalCount: Int {
        items.count
    }
    
    var progressText: String {
        "\(packedCount)/\(totalCount)"
    }
    
    var isComplete: Bool {
        totalCount > 0 && packedCount == totalCount
    }
}

// MARK: - Packing Item

@Model
final class PackingItemModel {
    var id: UUID = UUID()
    var name: String = ""
    var isPacked: Bool = false
    var quantity: Int = 0
    var sortOrder: Int = 0
    
    var category: PackingCategoryModel?
    
    init(
        name: String = "",
        isPacked: Bool = false,
        quantity: Int = 1,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.isPacked = isPacked
        self.quantity = quantity
        self.sortOrder = sortOrder
    }
}
