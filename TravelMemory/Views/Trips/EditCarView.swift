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
    
    @State private var company: String = ""
    @State private var vehicleType: String = ""
    @State private var pickupTime: Date = Date()
    @State private var dropoffTime: Date = Date()
    @State private var pickupLocation: String = ""
    @State private var dropoffLocation: String = ""
    @State private var confirmationCode: String = ""
    @State private var isPrepaid: Bool = false
    @State private var showDeleteConfirm = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.voyagerBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: VoyagerSpacing.stackLarge) {
                        formField(title: "COMPANY", placeholder: "Sixt", text: $company)
                        formField(title: "VEHICLE TYPE", placeholder: "BMW 5 Series", text: $vehicleType)
                        
                        dateField(title: "PICKUP", date: $pickupTime)
                        formField(title: "PICKUP LOCATION", placeholder: "Airport Terminal 2", text: $pickupLocation)
                        
                        dateField(title: "DROP-OFF", date: $dropoffTime)
                        formField(title: "DROP-OFF LOCATION", placeholder: "Airport Terminal 2", text: $dropoffLocation)
                        
                        formField(title: "CONFIRMATION CODE", placeholder: "SX884920", text: $confirmationCode)
                        
                        // Pre-paid toggle
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PAYMENT")
                                .font(VoyagerFont.labelCapsFallback)
                                .tracking(1.0)
                                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                            
                            Toggle(isOn: $isPrepaid) {
                                Text("Pre-paid")
                                    .font(VoyagerFont.bodyLargeFallback)
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
                                .font(VoyagerFont.labelCapsFallback)
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
            .navigationTitle("Edit Car Rental")
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
                    modelContext.delete(car)
                    try? modelContext.save()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { loadValues() }
    }
    
    private func loadValues() {
        company = car.company
        vehicleType = car.vehicleType
        pickupTime = car.pickupTime
        dropoffTime = car.dropoffTime
        pickupLocation = car.pickupLocation
        dropoffLocation = car.dropoffLocation
        confirmationCode = car.confirmationCode
        isPrepaid = car.isPrepaid
    }
    
    private func save() {
        car.company = company
        car.vehicleType = vehicleType
        car.pickupTime = pickupTime
        car.dropoffTime = dropoffTime
        car.pickupLocation = pickupLocation
        car.dropoffLocation = dropoffLocation
        car.confirmationCode = confirmationCode.uppercased()
        car.isPrepaid = isPrepaid
        try? modelContext.save()
        dismiss()
    }
    
    private func formField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(VoyagerFont.labelCapsFallback)
                .tracking(1.0)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            TextField(placeholder, text: text)
                .font(VoyagerFont.bodyLargeFallback)
                .foregroundStyle(Color.voyagerOnSurface)
                .padding(14)
                .background(Color.voyagerInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                        .stroke(Color.voyagerInputBorder, lineWidth: 1)
                )
        }
    }
    
    private func dateField(title: String, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(VoyagerFont.labelCapsFallback)
                .tracking(1.0)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            DatePicker("", selection: date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(Color.voyagerPrimary)
                .padding(10)
                .background(Color.voyagerInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
        }
    }
}
