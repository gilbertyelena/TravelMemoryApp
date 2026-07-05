//
//  VoyagerFormFields.swift
//  TravelMemory
//
//  Shared labeled form controls used by the Edit sheets.
//

import SwiftUI

/// Labeled single-line text input with the Voyager input styling.
struct VoyagerFormField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(VoyagerFont.labelCaps)
                .tracking(1.0)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            TextField(placeholder, text: $text)
                .font(VoyagerFont.bodyLarge)
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
}

/// Segmented idea/planned/booked selector used by all item editors.
struct VoyagerStatusPicker: View {
    @Binding var status: ItineraryItemStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STATUS")
                .font(VoyagerFont.labelCaps)
                .tracking(1.0)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            HStack(spacing: 8) {
                ForEach(ItineraryItemStatus.allCases, id: \.rawValue) { candidate in
                    Button {
                        status = candidate
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: candidate.icon)
                                .font(.system(size: 11))
                            Text(candidate.label.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.5)
                        }
                        .foregroundStyle(status == candidate ? .white : Color.voyagerOnSurfaceVariant)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            status == candidate
                            ? Color(hex: candidate.colorHex).opacity(0.85)
                            : Color.voyagerSurfaceContainerHigh
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Labeled cost input: short currency code plus amount.
struct VoyagerCostField: View {
    @Binding var costText: String
    @Binding var currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("COST")
                .font(VoyagerFont.labelCaps)
                .tracking(1.0)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            HStack(spacing: 8) {
                TextField("EUR", text: $currencyCode)
                    .font(VoyagerFont.bodyLarge)
                    .foregroundStyle(Color.voyagerOnSurface)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .frame(width: 64)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 14)
                    .background(Color.voyagerInputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                            .stroke(Color.voyagerInputBorder, lineWidth: 1)
                    )

                TextField("0.00", text: $costText)
                    .font(VoyagerFont.bodyLarge)
                    .foregroundStyle(Color.voyagerOnSurface)
                    .keyboardType(.decimalPad)
                    .padding(14)
                    .background(Color.voyagerInputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                            .stroke(Color.voyagerInputBorder, lineWidth: 1)
                    )
            }
        }
    }

    /// Parses user cost input tolerantly ("1,234.50", "12,50" → Double)
    static func parse(_ text: String) -> Double {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
        if let value = Double(cleaned) { return value }
        // European decimal comma
        let swapped = cleaned.replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        if let value = Double(swapped) { return value }
        // Thousands separators
        let stripped = cleaned.replacingOccurrences(of: ",", with: "")
        return Double(stripped) ?? 0
    }

    static func format(_ cost: Double) -> String {
        guard cost > 0 else { return "" }
        return cost.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", cost)
            : String(format: "%.2f", cost)
    }
}

/// Small status badge for timeline/agenda rows (hidden when booked).
struct ItemStatusBadge: View {
    let status: ItineraryItemStatus

    var body: some View {
        if status != .booked {
            HStack(spacing: 3) {
                Image(systemName: status.icon)
                    .font(.system(size: 8))
                Text(status.label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
            }
            .foregroundStyle(Color(hex: status.colorHex))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(hex: status.colorHex).opacity(0.12))
            .clipShape(Capsule())
        }
    }
}

/// Labeled compact date picker with the Voyager input styling.
/// When `timeZone` is set, the picker reads and writes wall-clock time
/// in that zone — so a 19:30 Munich dinner entered from London is
/// stored as 19:30 *in Munich*, not 19:30 BST.
struct VoyagerDateField: View {
    let title: String
    @Binding var date: Date
    var displayedComponents: DatePickerComponents = [.date, .hourAndMinute]
    var timeZone: TimeZone? = nil

    private var zoneSuffix: String {
        guard let timeZone, timeZone.identifier != TimeZone.current.identifier else { return "" }
        return " · \(timeZone.abbreviation() ?? timeZone.identifier)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title + zoneSuffix)
                .font(VoyagerFont.labelCaps)
                .tracking(1.0)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            DatePicker("", selection: $date, displayedComponents: displayedComponents)
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(Color.voyagerPrimary)
                .padding(10)
                .background(Color.voyagerInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                .environment(\.timeZone, timeZone ?? .current)
        }
    }
}
