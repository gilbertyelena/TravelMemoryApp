//
//  EditActivityView.swift
//  TravelMemory
//
//  Edit a trip activity (diving, boat trip, tour, etc.)
//  with category picker, times, provider, and notes.
//

import SwiftUI
import SwiftData

struct EditActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var activity: TripActivity
    /// True when editing a just-created draft — dismissed without saving,
    /// the draft is deleted again so no empty rows linger in the timeline.
    var isNew: Bool = false
    @State private var isFinalized = false
    
    @State private var activityName = ""
    @State private var provider = ""
    @State private var location = ""
    @State private var selectedCategory: ActivityCategory = .other
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var confirmationCode = ""
    @State private var itemStatus: ItineraryItemStatus = .booked
    @State private var costText = ""
    @State private var currencyText = ""
    @State private var notes = ""
    @State private var priceInfo = ""
    @State private var showDeleteConfirm = false
    
    /// Zone this event's times are entered and shown in
    private var eventZone: TimeZone {
        TimeZone(identifier: activity.timeZoneID) ?? activity.trip?.timeZone ?? .current
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.voyagerBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: VoyagerSpacing.stackLarge) {
                        VoyagerFormField(title: "ACTIVITY NAME", placeholder: "e.g. Scuba Diving", text: $activityName)
                        
                        // Category chips
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CATEGORY")
                                .font(VoyagerFont.labelCaps)
                                .tracking(1.0)
                                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 8) {
                                ForEach(ActivityCategory.allCases, id: \.rawValue) { cat in
                                    categoryChip(cat)
                                }
                            }
                        }
                        
                        VoyagerFormField(title: "PROVIDER", placeholder: "e.g. Blue Ocean Divers", text: $provider)
                        VoyagerFormField(title: "LOCATION", placeholder: "Meeting point or venue", text: $location)
                        
                        VoyagerDateField(title: "START TIME", date: $startTime, timeZone: eventZone)
                        VoyagerDateField(title: "END TIME", date: $endTime, timeZone: eventZone)
                        
                        HStack(spacing: 10) {
                            VoyagerStatusPicker(status: $itemStatus)

                        VoyagerFormField(title: "CONFIRMATION", placeholder: "Ref code", text: $confirmationCode)

                        VoyagerCostField(costText: $costText, currencyCode: $currencyText)
                            VoyagerFormField(title: "PRICE", placeholder: "€85pp", text: $priceInfo)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NOTES")
                                .font(VoyagerFont.labelCaps)
                                .tracking(1.0)
                                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                            TextField("Special instructions, what to bring...", text: $notes, axis: .vertical)
                                .font(VoyagerFont.bodyLarge)
                                .foregroundStyle(Color.voyagerOnSurface)
                                .lineLimit(2...4)
                                .padding(12)
                                .background(Color.voyagerInputBackground)
                                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                                .overlay(
                                    RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                                        .stroke(Color.voyagerInputBorder, lineWidth: 1)
                                )
                        }
                        
                        Button { save() } label: { Text("SAVE") }
                            .buttonStyle(VoyagerPrimaryButtonStyle())
                            .padding(.top, 8)
                        
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Text("DELETE ACTIVITY")
                                .font(VoyagerFont.labelCaps)
                                .tracking(0.6)
                                .foregroundStyle(Color.voyagerError)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle(isNew ? "Add Activity" : "Edit Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
            .alert("Delete Activity?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    isFinalized = true
                    TripNotifications.cancel(itemID: activity.id)
                    modelContext.delete(activity)
                    modelContext.saveOrLog()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { loadValues() }
        .onDisappear {
            // Draft dismissed without saving — remove it again
            if isNew && !isFinalized {
                modelContext.delete(activity)
                modelContext.saveOrLog()
            }
        }
    }
    
    // MARK: - Category Chip
    
    private func categoryChip(_ cat: ActivityCategory) -> some View {
        let isSelected = selectedCategory == cat
        let catColor = Color(hex: cat.color)
        
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedCategory = cat }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: cat.icon)
                    .font(.system(size: 12))
                Text(cat.label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isSelected ? .white : catColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? catColor : catColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(catColor.opacity(isSelected ? 0 : 0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Load / Save
    
    private func loadValues() {
        activityName = activity.activityName
        provider = activity.provider
        location = activity.location
        selectedCategory = activity.category
        startTime = activity.startTime
        endTime = activity.endTime
        confirmationCode = activity.confirmationCode
        itemStatus = activity.status
        costText = VoyagerCostField.format(activity.cost)
        currencyText = activity.currencyCode
        notes = activity.notes
        priceInfo = activity.priceInfo
    }
    
    private func save() {
        isFinalized = true
        activity.activityName = activityName
        activity.provider = provider
        activity.location = location
        activity.category = selectedCategory
        activity.startTime = startTime
        activity.endTime = endTime
        activity.confirmationCode = confirmationCode
        activity.status = itemStatus
        activity.cost = VoyagerCostField.parse(costText)
        activity.currencyCode = currencyText.trimmingCharacters(in: .whitespaces).uppercased()
        activity.timeZoneID = eventZone.identifier
        activity.notes = notes
        activity.priceInfo = priceInfo
        modelContext.saveOrLog()
        TripNotifications.resync(item: activity, itemID: activity.id)
        dismiss()
    }
    
    // MARK: - Helpers
    
    
}
