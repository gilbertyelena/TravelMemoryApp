//
//  TripShareReceiveView.swift
//  TravelMemory
//
//  Shown when a .travelsteward file is opened (AirDrop, Messages,
//  Files). Previews the trips inside and imports on confirmation.
//  Import merges by id, so opening the same file twice is harmless.
//

import SwiftUI
import SwiftData

struct TripShareReceiveView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let fileURL: URL

    @State private var archive: BackupArchive?
    @State private var errorText: String?
    @State private var summaryText: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.voyagerBackground.ignoresSafeArea()

                if let errorText {
                    errorState(errorText)
                } else if let summaryText {
                    doneState(summaryText)
                } else if let archive {
                    previewState(archive)
                } else {
                    ProgressView()
                        .tint(Color.voyagerPrimary)
                }
            }
            .navigationTitle("Shared Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(summaryText == nil ? "Cancel" : "Done") { dismiss() }
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { load() }
    }

    // MARK: - States

    private func previewState(_ archive: BackupArchive) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "airplane.arrival")
                .font(.system(size: 40))
                .foregroundStyle(Color.voyagerPrimaryAccent)

            Text(archive.trips.count == 1
                 ? "Someone sent you a trip"
                 : "Someone sent you \(archive.trips.count) trips")
                .font(VoyagerFont.headlineMedium)
                .foregroundStyle(Color.voyagerOnSurface)

            VStack(spacing: 10) {
                ForEach(archive.trips, id: \.id) { trip in
                    tripCard(trip)
                }
            }
            .padding(.horizontal, VoyagerSpacing.marginMain)

            Button {
                importTrips()
            } label: {
                Text("ADD TO MY TRIPS")
            }
            .buttonStyle(VoyagerPrimaryButtonStyle())
            .padding(.horizontal, VoyagerSpacing.marginMain)
        }
    }

    private func tripCard(_ trip: BackupArchive.TripBackup) -> some View {
        let counts: [(Int, String)] = [
            (trip.flights.count, "flight"),
            (trip.hotels.count, "stay"),
            (trip.carRentals.count, "car"),
            (trip.dining.count, "restaurant"),
            (trip.activities.count, "activity"),
        ]
        let summary = counts.filter { $0.0 > 0 }.map { count, noun in
            let plural = noun == "activity" ? "activities" : noun + "s"
            return "\(count) \(count == 1 ? noun : plural)"
        }

        return VStack(alignment: .leading, spacing: 4) {
            Text(trip.name.isEmpty ? trip.destination : trip.name)
                .font(VoyagerFont.bodyLargeSemibold)
                .foregroundStyle(Color.voyagerOnSurface)
            Text(dateRange(trip))
                .font(VoyagerFont.bodySmall)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            if !summary.isEmpty {
                Text(summary.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.voyagerSurfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
    }

    private func doneState(_ text: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.voyagerPrimaryAccent)
            Text("Trip added")
                .font(VoyagerFont.headlineMedium)
                .foregroundStyle(Color.voyagerOnSurface)
            Text(text)
                .font(VoyagerFont.bodySmall)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func errorState(_ text: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Color.voyagerTertiary)
            Text("Couldn't open that file")
                .font(VoyagerFont.headlineMedium)
                .foregroundStyle(Color.voyagerOnSurface)
            Text(text)
                .font(VoyagerFont.bodySmall)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Actions

    private func load() {
        do {
            archive = try BackupService.peek(at: fileURL)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func importTrips() {
        do {
            let summary = try BackupService.restore(from: fileURL, context: modelContext)
            // Fresh reminders for whatever just arrived
            if let trips = try? modelContext.fetch(FetchDescriptor<Trip>()) {
                for trip in trips { TripNotifications.resync(trip: trip) }
            }
            CalendarSyncService.requestResync(context: modelContext)
            summaryText = summary.text
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func dateRange(_ trip: BackupArchive.TripBackup) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return "\(fmt.string(from: trip.startDate)) – \(fmt.string(from: trip.endDate))"
    }
}
