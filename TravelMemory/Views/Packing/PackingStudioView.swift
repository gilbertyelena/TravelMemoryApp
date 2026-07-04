//
//  PackingListView.swift
//  TravelMemory
//
//  Persistent packing checklist linked to a trip.
//  Categories and items are saved to SwiftData.
//

import SwiftUI
import SwiftData

struct PackingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var trip: Trip
    
    @State private var showAddCategory = false
    @State private var newCategoryName = ""
    @State private var newItemText = ""
    @State private var addingItemToCategory: UUID?
    @State private var editingItem: PackingItemModel?
    @State private var editItemName = ""
    
    private var sortedCategories: [PackingCategoryModel] {
        trip.packingCategories.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    private var totalItems: Int {
        trip.packingCategories.flatMap(\.items).count
    }
    
    private var packedItems: Int {
        trip.packingCategories.flatMap(\.items).filter(\.isPacked).count
    }
    
    private var progress: Double {
        totalItems > 0 ? Double(packedItems) / Double(totalItems) : 0
    }
    
    var body: some View {
        ZStack {
            Color.voyagerBackground.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: VoyagerSpacing.stackLarge) {
                    // Progress header
                    if totalItems > 0 {
                        progressHeader
                            .padding(.horizontal, VoyagerSpacing.marginMain)
                    }
                    
                    // Suggested categories (when empty)
                    if trip.packingCategories.isEmpty {
                        emptyState
                    }
                    
                    // Category cards
                    ForEach(sortedCategories, id: \.id) { category in
                        categoryCard(category)
                    }
                    .padding(.horizontal, VoyagerSpacing.marginMain)
                    
                    // Add category button
                    Button {
                        showAddCategory = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 16))
                            Text("ADD CATEGORY")
                                .font(VoyagerFont.labelCapsFallback)
                                .tracking(0.6)
                        }
                        .foregroundStyle(Color.voyagerPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.voyagerPrimary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                        .overlay(
                            RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                                .foregroundStyle(Color.voyagerPrimary.opacity(0.3))
                        )
                    }
                    .padding(.horizontal, VoyagerSpacing.marginMain)
                }
                .padding(.bottom, 120)
                .padding(.top, 8)
            }
        }
        .navigationTitle("Packing List")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        addSuggestedCategories()
                    } label: {
                        Label("Add Suggested Items", systemImage: "sparkles")
                    }
                    
                    if totalItems > 0 {
                        Button {
                            uncheckAll()
                        } label: {
                            Label("Uncheck All", systemImage: "arrow.counterclockwise")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Color.voyagerPrimary)
                }
            }
        }
        .alert("New Category", isPresented: $showAddCategory) {
            TextField("e.g. Documents, Clothes", text: $newCategoryName)
            Button("Add") {
                addCategory(name: newCategoryName)
                newCategoryName = ""
            }
            Button("Cancel", role: .cancel) { newCategoryName = "" }
        }
        .alert("Edit Item", isPresented: Binding(
            get: { editingItem != nil },
            set: { if !$0 { editingItem = nil } }
        )) {
            TextField("Item name", text: $editItemName)
            Button("Save") {
                if let item = editingItem {
                    item.name = editItemName
                    try? modelContext.save()
                }
                editingItem = nil
            }
            Button("Delete", role: .destructive) {
                if let item = editingItem {
                    modelContext.delete(item)
                    try? modelContext.save()
                }
                editingItem = nil
            }
            Button("Cancel", role: .cancel) { editingItem = nil }
        }
    }
    
    // MARK: - Progress Header
    
    private var progressHeader: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(packedItems) of \(totalItems) packed")
                        .font(VoyagerFont.bodyLargeFallback)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.voyagerOnSurface)
                    Text(progress >= 1.0 ? "All packed! ✈️" : "Keep going...")
                        .font(VoyagerFont.bodySmallFallback)
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(progress >= 1.0 ? Color.voyagerPrimaryAccent : Color.voyagerPrimary)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.voyagerSurfaceContainerHigh)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progress >= 1.0 ? Color.voyagerPrimaryAccent : Color.voyagerPrimary)
                        .frame(width: geo.size.width * progress, height: 6)
                        .animation(.easeOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .background(Color.voyagerSurfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.voyagerPrimary.opacity(0.06))
                    .frame(width: 100, height: 100)
                Image(systemName: "suitcase")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(Color.voyagerPrimary.opacity(0.6))
            }
            
            VStack(spacing: 6) {
                Text("Start Your Packing List")
                    .font(VoyagerFont.headlineMediumFallback)
                    .foregroundStyle(Color.voyagerOnSurface)
                Text("Add categories or tap ••• for suggested items")
                    .font(VoyagerFont.bodySmallFallback)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Category Card
    
    private func categoryCard(_ category: PackingCategoryModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: category.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: category.colorHex))
                    Text(category.name)
                        .font(VoyagerFont.bodyLargeFallback)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.voyagerOnSurface)
                }
                
                Spacer()
                
                if category.totalCount > 0 {
                    Text(category.progressText)
                        .font(VoyagerFont.labelCapsFallback)
                        .foregroundStyle(category.isComplete ? Color.voyagerPrimaryAccent : Color.voyagerOnSurfaceVariant)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(category.isComplete ? Color.voyagerPrimaryAccent.opacity(0.12) : Color.voyagerSurfaceVariant)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                // Delete category
                Button {
                    modelContext.delete(category)
                    try? modelContext.save()
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.voyagerOnSurfaceVariant.opacity(0.4))
                }
            }
            
            // Items
            let sortedItems = category.items.sorted { $0.sortOrder < $1.sortOrder }
            ForEach(sortedItems, id: \.id) { item in
                itemRow(item)
            }
            
            // Add item inline
            if addingItemToCategory == category.id {
                HStack(spacing: 8) {
                    Circle()
                        .stroke(Color.voyagerOutlineVariant, lineWidth: 2)
                        .frame(width: 20, height: 20)
                    
                    TextField("Item name", text: $newItemText)
                        .font(VoyagerFont.bodyLargeFallback)
                        .foregroundStyle(Color.voyagerOnSurface)
                        .onSubmit {
                            addItem(to: category)
                        }
                    
                    Button {
                        addItem(to: category)
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.voyagerPrimary)
                    }
                    
                    Button {
                        addingItemToCategory = nil
                        newItemText = ""
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Button {
                    addingItemToCategory = category.id
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 12))
                        Text("Add item")
                            .font(VoyagerFont.bodySmallFallback)
                    }
                    .foregroundStyle(Color.voyagerPrimary.opacity(0.7))
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(14)
        .background(Color.voyagerSurfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerRadius.large)
                .stroke(Color.voyagerOutlineVariant.opacity(0.2), lineWidth: 0.5)
        )
    }
    
    // MARK: - Item Row
    
    private func itemRow(_ item: PackingItemModel) -> some View {
        HStack(spacing: 12) {
            // Checkbox
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    item.isPacked.toggle()
                    try? modelContext.save()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(item.isPacked ? Color.voyagerPrimary : .clear)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().stroke(
                                item.isPacked ? Color.voyagerPrimary : Color.voyagerOutlineVariant,
                                lineWidth: 2
                            )
                        )
                    
                    if item.isPacked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.voyagerBackground)
                    }
                }
            }
            
            // Item name (tap to edit)
            Button {
                editingItem = item
                editItemName = item.name
            } label: {
                Text(item.name)
                    .font(VoyagerFont.bodyLargeFallback)
                    .foregroundStyle(Color.voyagerOnSurface)
                    .strikethrough(item.isPacked)
                    .opacity(item.isPacked ? 0.5 : 1)
                
            }
            
            Spacer()
            
            if item.quantity > 1 {
                Text("×\(item.quantity)")
                    .font(VoyagerFont.labelCapsFallback)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }
        }
        .padding(.vertical, 3)
    }
    
    // MARK: - Actions
    
    private func addCategory(name: String) {
        guard !name.isEmpty else { return }
        let iconMap: [(String, String, String)] = [
            ("document", "folder.fill", "#0A85FF"),
            ("tech", "desktopcomputer", "#FF6B35"),
            ("cloth", "tshirt.fill", "#8B5CF6"),
            ("toilet", "drop.fill", "#06B6D4"),
            ("med", "cross.case.fill", "#EF4444"),
            ("food", "fork.knife", "#F59E0B"),
            ("shoe", "shoe.fill", "#10B981"),
        ]
        
        let lower = name.lowercased()
        let match = iconMap.first { lower.contains($0.0) }
        
        let category = PackingCategoryModel(
            name: name,
            icon: match?.1 ?? "bag.fill",
            colorHex: match?.2 ?? "#0A85FF",
            sortOrder: trip.packingCategories.count
        )
        category.trip = trip
        modelContext.insert(category)
        try? modelContext.save()
    }
    
    private func addItem(to category: PackingCategoryModel) {
        guard !newItemText.isEmpty else { return }
        let item = PackingItemModel(
            name: newItemText,
            sortOrder: category.items.count
        )
        item.category = category
        modelContext.insert(item)
        try? modelContext.save()
        newItemText = ""
        // Keep the add field open for fast entry
    }
    
    private func uncheckAll() {
        for category in trip.packingCategories {
            for item in category.items {
                item.isPacked = false
            }
        }
        try? modelContext.save()
    }
    
    private func addSuggestedCategories() {
        let suggestions: [(String, String, String, [String])] = [
            ("Documents", "folder.fill", "#0A85FF", ["Passport", "Boarding pass", "Travel insurance", "Hotel confirmation"]),
            ("Clothes", "tshirt.fill", "#8B5CF6", ["Underwear", "Socks", "T-shirts", "Pants", "Jacket"]),
            ("Toiletries", "drop.fill", "#06B6D4", ["Toothbrush", "Toothpaste", "Deodorant", "Shampoo", "Sunscreen"]),
            ("Tech", "desktopcomputer", "#FF6B35", ["Phone charger", "Adapter", "Headphones", "Power bank"]),
            ("Essentials", "bag.fill", "#10B981", ["Wallet", "Keys", "Medications", "Snacks", "Water bottle"]),
        ]
        
        for (i, (name, icon, color, items)) in suggestions.enumerated() {
            // Skip if category already exists
            if trip.packingCategories.contains(where: { $0.name == name }) { continue }
            
            let category = PackingCategoryModel(
                name: name,
                icon: icon,
                colorHex: color,
                sortOrder: trip.packingCategories.count + i
            )
            category.trip = trip
            modelContext.insert(category)
            
            for (j, itemName) in items.enumerated() {
                let item = PackingItemModel(name: itemName, sortOrder: j)
                item.category = category
                modelContext.insert(item)
            }
        }
        try? modelContext.save()
    }
}
