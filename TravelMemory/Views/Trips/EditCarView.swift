//
//  EditCarView.swift
//  TravelMemory
//
//  Edit all fields of a car rental booking.
//

import SwiftUI
import SwiftData

struct EditCarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var car: CarRentalBooking
    /// True when editing a just-created draft — dismissed without saving,
    /// the draft is deleted again so no empty rows linger in the timeline.
    var isNew: Bool = false
    @State private var isFinalized = false
    
    @State private var company: String = ""
    @State private var vehicleType: String = ""
    @State private var pickupTime: Date = Date()
    @State private var dropoffTime: Date = Date()
    @State private var pickupLocation: String = ""
    @State private var dropoffLocation: String = ""
    @State private var confirmationCode: String = ""
    @State private var itemStatus: ItineraryItemStatus = .booked
    @State private var costText = ""
    @State private var currencyText = ""
    @State private var isPrepaid: Bool = false
    @State private var showDeleteConfirm = false
    
    /// Zone this event's times are entered and shown in
    private var eventZone: TimeZone {
        TimeZone(identifier: car.timeZoneID) ?? car.trip?.timeZone ?? .current
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.voyagerBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: VoyagerSpacing.stackLarge) {
                        VoyagerFormField(title: "COMPANY", placeholder: "Sixt", text: $company)
                        VoyagerFormField(title: "VEHICLE TYPE", placeholder: "BMW 5 Series", text: $vehicleType)
                        
                        VoyagerDateField(title: "PICKUP", date: $pickupTime, timeZone: eventZone)
                        VoyagerFormField(title: "PICKUP LOCATION", placeholder: "Airport Terminal 2", text: $pickupLocation)
                        
                        VoyagerDateField(title: "DROP-OFF", date: $dropoffTime, timeZone: eventZone)
                        VoyagerFormField(title: "DROP-OFF LOCATION", placeholder: "Airport Terminal 2", text: $dropoffLocation)
                        
                        VoyagerStatusPicker(status: $itemStatus)

                        VoyagerFormField(title: "CONFIRMATION CODE", placeholder: "SX884920", text: $confirmationCode)

                        VoyagerCostField(costText: $costText, currencyCode: $currencyText)
                        
                        // Pre-paid toggle
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PAYMENT")
                                .font(VoyagerFont.labelCaps)
                                .tracking(1.0)
                                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                            
                            Toggle(isOn: $isPrepaid) {
                                Text("Pre-paid")
                                    .font(VoyagerFont.bodyLarge)
                                    .foregroundStyle(Color.voyagerOnSurface)
                            }
                            .tint(Color.voyagerPrimary)
                            .padding(14)
                            .background(Color.voyagerInputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                        }
                        
                        Button { save() } label: { Text("SAVE") }
                            .buttonStyle(VoyagerPrimaryButtonStyle())
                            .padding(.top, 8)
                        
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Text("DELETE CAR RENTAL")
                                .font(VoyagerFont.labelCaps)
                                .tracking(0.6)
                                .foregroundStyle(Color.voyagerError)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }
                    .padding(.horizontal, VoyagerSpacing.marginMain)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle(isNew ? "Add Car Rental" : "Edit Car Rental")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
            .alert("Delete Car Rental?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    isFinalized = true
                    TripNotifications.cancel(itemID: car.id)
                    modelContext.delete(car)
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
                modelContext.delete(car)
                modelContext.saveOrLog()
            }
        }
    }
    
    private func loadValues() {
        company = car.company
        vehicleType = car.vehicleType
        pickupTime = car.pickupTime
        dropoffTime = car.dropoffTime
        pickupLocation = car.pickupLocation
        dropoffLocation = car.dropoffLocation
        confirmationCode = car.confirmationCode
        itemStatus = car.status
        costText = VoyagerCostField.format(car.cost)
        currencyText = car.currencyCode
        isPrepaid = car.isPrepaid
    }
    
    private func save() {
        isFinalized = true
        car.company = company
        car.vehicleType = vehicleType
        car.pickupTime = pickupTime
        car.dropoffTime = dropoffTime
        car.pickupLocation = pickupLocation
        car.dropoffLocation = dropoffLocation
        car.confirmationCode = confirmationCode.uppercased()
        car.status = itemStatus
        car.cost = VoyagerCostField.parse(costText)
        car.currencyCode = currencyText.trimmingCharacters(in: .whitespaces).uppercased()
        car.timeZoneID = eventZone.identifier
        car.isPrepaid = isPrepaid
        modelContext.saveOrLog()
        TripNotifications.resync(item: car, itemID: car.id)
        CalendarSyncService.requestResync(context: modelContext)
        dismiss()
    }
    
    
}
