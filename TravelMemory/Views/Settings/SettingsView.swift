//
//  SettingsView.swift
//  TravelMemory
//
//  App preferences: reminders, currency, and sync status — replaces
//  the old "Coming Soon" profile placeholder.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("remindersEnabled") private var remindersEnabled = true

    // Backup state
    @State private var backupShareURL: URL?
    @State private var showRestorePicker = false
    @State private var restoreMessage: String?
    @State private var backupError: String?
    @AppStorage("checkinLeadHours") private var checkinLeadHours = 24
    @AppStorage("reminderLeadHours") private var reminderLeadHours = 2
    @AppStorage("defaultCurrencyCode") private var defaultCurrency = ""

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: VoyagerSpacing.stackLarge) {
                VoyagerTopBar()

                header

                section("REMINDERS") {
                    toggleRow(
                        icon: "bell.badge",
                        title: "Itinerary reminders",
                        subtitle: "Check-in, reservations, pickups",
                        isOn: $remindersEnabled
                    )

                    if remindersEnabled {
                        pickerRow(
                            icon: "airplane",
                            title: "Flight check-in",
                            selection: $checkinLeadHours,
                            options: [(12, "12h before"), (24, "24h before"), (48, "48h before")]
                        )
                        pickerRow(
                            icon: "fork.knife",
                            title: "Reservations & activities",
                            selection: $reminderLeadHours,
                            options: [(1, "1h before"), (2, "2h before"), (3, "3h before")]
                        )
                    }
                }

                section("PREFERENCES") {
                    HStack(spacing: 12) {
                        settingIcon("banknote")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default currency")
                                .font(VoyagerFont.bodyMedium)
                                .foregroundStyle(Color.voyagerOnSurface)
                            Text("Pre-filled on new cost entries")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                        }
                        Spacer()
                        TextField("GBP", text: $defaultCurrency)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.voyagerPrimary)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.center)
                            .frame(width: 64)
                            .padding(.vertical, 8)
                            .background(Color.voyagerInputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onChange(of: defaultCurrency) { _, newValue in
                                defaultCurrency = String(newValue.uppercased().prefix(3))
                            }
                    }
                    .padding(14)
                }

                section("BACKUP") {
                    Button {
                        exportBackup()
                    } label: {
                        HStack(spacing: 12) {
                            settingIcon("square.and.arrow.up")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Export backup")
                                    .font(VoyagerFont.bodyMedium)
                                    .foregroundStyle(Color.voyagerOnSurface)
                                Text("Every trip and vault document in one file — save it to iCloud Drive")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 54).opacity(0.3)

                    Button {
                        showRestorePicker = true
                    } label: {
                        HStack(spacing: 12) {
                            settingIcon("square.and.arrow.down")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Restore from backup")
                                    .font(VoyagerFont.bodyMedium)
                                    .foregroundStyle(Color.voyagerOnSurface)
                                Text("Merges by id — never creates duplicates")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if let message = restoreMessage ?? backupError {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(backupError == nil ? Color.voyagerPrimaryAccent : Color.voyagerError)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                section("SYNC") {
                    HStack(spacing: 12) {
                        settingIcon(CloudSyncConfig.isEnabled ? "icloud.fill" : "icloud.slash")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("iCloud sync")
                                .font(VoyagerFont.bodyMedium)
                                .foregroundStyle(Color.voyagerOnSurface)
                            Text(CloudSyncConfig.isEnabled
                                 ? "On — syncing via your private iCloud"
                                 : "Off — needs an Apple Developer account. Enable steps are documented in TravelMemoryApp.swift.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(14)
                }

                section("ABOUT") {
                    HStack(spacing: 12) {
                        settingIcon("info.circle")
                        Text("Version")
                            .font(VoyagerFont.bodyMedium)
                            .foregroundStyle(Color.voyagerOnSurface)
                        Spacer()
                        Text(appVersion)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                    .padding(14)
                }
            }
            .padding(.bottom, 120)
        }
        .background(Color.voyagerBackground)
        .sheet(isPresented: Binding(
            get: { backupShareURL != nil },
            set: { if !$0 { backupShareURL = nil } }
        )) {
            if let url = backupShareURL {
                ShareSheet(items: [url])
                    .presentationDetents([.medium, .large])
            }
        }
        .fileImporter(isPresented: $showRestorePicker, allowedContentTypes: [.json, .plainText]) { result in
            restoreMessage = nil
            backupError = nil
            switch result {
            case .success(let url):
                restoreBackup(from: url)
            case .failure(let error):
                backupError = error.localizedDescription
            }
        }
    }

    // MARK: - Backup Actions

    private func exportBackup() {
        restoreMessage = nil
        backupError = nil
        do {
            backupShareURL = try BackupService.export(context: modelContext)
        } catch {
            backupError = "Export failed: \(error.localizedDescription)"
        }
    }

    private func restoreBackup(from url: URL) {
        do {
            let summary = try BackupService.restore(from: url, context: modelContext)
            restoreMessage = summary.text

            // Re-arm reminders and the widget for restored trips
            if let trips = try? modelContext.fetch(FetchDescriptor<Trip>()) {
                for trip in trips { TripNotifications.resync(trip: trip) }
            }
            WidgetSnapshotService.refresh(context: modelContext)
        } catch {
            backupError = error.localizedDescription
        }
    }

    // MARK: - Building Blocks

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(VoyagerFont.headlineLarge)
                .foregroundStyle(Color.voyagerOnSurface)
        }
        .padding(.horizontal, VoyagerSpacing.marginMain)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(VoyagerFont.labelCaps)
                .tracking(1.0)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .voyagerCard()
        }
        .padding(.horizontal, VoyagerSpacing.marginMain)
    }

    private func settingIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16))
            .foregroundStyle(Color.voyagerPrimary)
            .frame(width: 28)
    }

    private func toggleRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            settingIcon(icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(VoyagerFont.bodyMedium)
                    .foregroundStyle(Color.voyagerOnSurface)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.voyagerPrimaryAccent)
        }
        .padding(14)
    }

    private func pickerRow(icon: String, title: String, selection: Binding<Int>, options: [(Int, String)]) -> some View {
        HStack(spacing: 12) {
            settingIcon(icon)
            Text(title)
                .font(VoyagerFont.bodyMedium)
                .foregroundStyle(Color.voyagerOnSurface)
            Spacer()
            Menu {
                ForEach(options, id: \.0) { value, label in
                    Button(label) { selection.wrappedValue = value }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(options.first { $0.0 == selection.wrappedValue }?.1 ?? "\(selection.wrappedValue)h")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundStyle(Color.voyagerPrimary)
            }
        }
        .padding(14)
    }
}
