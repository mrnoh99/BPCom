import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Reading.date) private var readings: [Reading]

    @AppStorage(SettingsKey.ownerName) private var ownerName = SettingsKey.defaultOwnerName
    @AppStorage(SettingsKey.iCloudSync) private var iCloudSync = true

    /// Value of the toggle when the app was launched (the store is configured at launch).
    @State private var launchICloudSync = UserDefaults.standard.object(forKey: SettingsKey.iCloudSync) as? Bool ?? true

    @State private var exportDoc: CSVDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    /// Info under Export/Import: collapsed whenever Settings opens, expanded after an import/export.
    @State private var dataInfoExpanded = false
    @State private var dataResult: String?
    @State private var dataResultIsError = false

    @AppStorage(SettingsKey.healthEnabled) private var healthEnabled = true
    @StateObject private var health = HealthSync.shared
    @Environment(\.openURL) private var openURL
    @State private var healthResult: String?

    @EnvironmentObject private var sync: CloudSyncMonitor

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    HStack {
                        Text("Name")
                        TextField("Name", text: $ownerName)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(Theme.label)
                    }
                }

                Section {
                    Button {
                        exportDoc = CSVDocument(text: CSV.export(readings))
                        showExporter = true
                    } label: {
                        Label("Export (CSV)", systemImage: "square.and.arrow.up")
                    }
                    .disabled(readings.isEmpty)

                    Button {
                        showImporter = true
                    } label: {
                        Label("Import (CSV)", systemImage: "square.and.arrow.down")
                    }

                    DisclosureGroup(isExpanded: $dataInfoExpanded) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let dataResult {
                                Text(dataResult)
                                    .font(.subheadline)
                                    .foregroundStyle(dataResultIsError ? Theme.high : Theme.normal)
                            }
                            Text("\(readings.count) readings stored.")
                                .font(.footnote)
                            Text("CSV format: \"Date Time\",\"Period\",\"Systolic (mmHg)\",\"Diastolic (mmHg)\",\"MAP (mmHg)\",\"Heart Rate (bpm)\",\"Weight (kg)\",\"Drug\",\"Note\" — e.g. \"2026. 11. 19. 06:54\",\"Morning\",\"141\",\"95\",\"110\",\"66\",\"84.5\",\"YES\",\"\"")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.vertical, 4)
                    } label: {
                        Label("Info", systemImage: "info.circle")
                            .foregroundStyle(Theme.secondaryText)
                    }
                } header: {
                    Text("Data")
                }

                if health.isAvailable {
                    Section {
                        Toggle(isOn: $healthEnabled) {
                            Label("Write to Health", systemImage: "heart.text.square")
                        }
                        .tint(Theme.orange)
                        .onChange(of: healthEnabled) { _, on in
                            if on { connectHealth() }
                        }
                        if healthEnabled {
                            Button {
                                sendAllToHealth()
                            } label: {
                                HStack {
                                    Label("Send All Readings to Health", systemImage: "arrow.up.heart")
                                    Spacer()
                                    if health.busy { ProgressView() }
                                }
                            }
                            .disabled(readings.isEmpty || health.busy)
                        }
                        HStack {
                            Text("Health Access")
                            Spacer()
                            Text(healthAccessText)
                                .foregroundStyle(health.access == .allowed ? Theme.normal : Theme.secondaryText)
                        }
                        .id(health.accessChecked)
                        if healthEnabled && health.access != .allowed {
                            Button {
                                if health.access == .notAsked {
                                    connectHealth()
                                } else if let url = URL(string: "x-apple-health://") {
                                    openURL(url)
                                }
                            } label: {
                                Label(health.access == .notAsked ? "Allow Health Access" : "Open Health App",
                                      systemImage: "heart")
                            }
                        }
                        if let healthResult {
                            Text(healthResult)
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        if let error = health.lastError {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(Theme.high)
                        }
                    } header: {
                        Text("Apple Health")
                    } footer: {
                        Text("Blood pressure, heart rate and weight are saved to the Health app. New, edited and deleted readings are updated automatically. Allow access in Health › Sharing › Apps › BP Companion.")
                    }
                }

                Section {
                    Toggle(isOn: $iCloudSync) {
                        Label("iCloud Sync", systemImage: "icloud")
                    }
                    .tint(Theme.orange)
                    HStack {
                        Text("iCloud Account")
                        Spacer()
                        Text(sync.account.text)
                            .foregroundStyle(sync.account == .available ? Theme.normal : Theme.secondaryText)
                    }
                    HStack {
                        Text("Status")
                        Spacer()
                        if sync.syncing { ProgressView().padding(.trailing, 4) }
                        Text(statusText)
                            .foregroundStyle(statusIsError ? Theme.high : Theme.secondaryText)
                            .multilineTextAlignment(.trailing)
                    }
                    if sync.cloudEnabled {
                        HStack {
                            Text("Last Sync")
                            Spacer()
                            Text(sync.lastSync.map { $0.formatted(.relative(presentation: .named)) } ?? "–")
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    if let error = sync.lastError ?? sync.setupError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Theme.high)
                    }
                } header: {
                    Text("iCloud")
                } footer: {
                    Text(iCloudSync != launchICloudSync
                         ? "Restart the app (swipe it away and open it again) to apply this change."
                         : "Readings are synced through your private iCloud database to every iPhone/iPad signed in with the same Apple ID. Changes usually appear on other devices within a minute while the app is open.")
                }

                #if DEBUG
                Section {
                    Button { addSampleData() } label: {
                        Label("Add Sample Data (debug)", systemImage: "wand.and.stars")
                    }
                }
                #endif

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion).foregroundStyle(Theme.secondaryText)
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Developed by Jaisung NOH MD 2026")
                        .font(.caption2)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .scrollContentBackground(.hidden)
            .readableWidth(700)
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .orangeNavigationBar()
            .fileExporter(isPresented: $showExporter,
                          document: exportDoc,
                          contentType: .commaSeparatedText,
                          defaultFilename: "BloodPressure_Data_\(Self.fileDate.string(from: .now))") { result in
                switch result {
                case .success: showDataResult("Exported \(readings.count) readings.")
                case .failure(let error): showDataResult("Export failed: \(error.localizedDescription)", error: true)
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
                switch result {
                case .success(let url): importCSV(url)
                case .failure(let error): showDataResult("Import failed: \(error.localizedDescription)", error: true)
                }
            }
            // Opening Settings again starts with the info collapsed.
            .onDisappear {
                dataInfoExpanded = false
                dataResult = nil
            }
        }
    }

    /// yyyyMMdd for the export file name (BloodPressure_Data_20261119.csv)
    private static let fileDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    private var statusText: String {
        if !launchICloudSync { return "Local only" }
        if sync.setupError != nil { return "iCloud unavailable – saved on this device" }
        if sync.account == .noAccount { return "Sign in to iCloud in the Settings app" }
        if sync.syncing { return "Syncing…" }
        if sync.lastError != nil { return "Sync error" }
        return sync.lastSync == nil ? "Waiting for first sync" : "Up to date"
    }

    private var statusIsError: Bool {
        launchICloudSync && (sync.setupError != nil || sync.lastError != nil)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func importCSV(_ url: URL) {
        do {
            showDataResult(try CSVImporter.importFile(at: url, into: context))
        } catch {
            showDataResult("Import failed: \(error.localizedDescription)", error: true)
        }
    }

    private func showDataResult(_ text: String, error: Bool = false) {
        dataResult = text
        dataResultIsError = error
        withAnimation { dataInfoExpanded = true }
    }

    // MARK: Apple Health

    /// Turned on: ask for permission, then copy all existing readings to Health.
    private func connectHealth() {
        Task {
            do {
                try await health.requestAuthorization()
                guard health.isAuthorized else {
                    healthResult = "Health access was not allowed. Turn it on in Health › Sharing › Apps › BP Companion."
                    return
                }
                let n = try await health.sendAll(readings)
                healthResult = "Connected. \(n) readings saved to Health."
            } catch {
                healthResult = "Could not connect to Health. Check that the HealthKit capability is enabled in Xcode › Signing & Capabilities."
                healthEnabled = false
            }
        }
    }

    private var healthAccessText: String {
        switch health.access {
        case .unavailable: return "Not available"
        case .notAsked: return "Not asked yet"
        case .allowed: return "Allowed"
        case .denied: return "Not allowed"
        }
    }

    private func sendAllToHealth() {
        Task {
            do {
                if !health.isAuthorized { try await health.requestAuthorization() }
                let n = try await health.sendAll(readings)
                healthResult = "\(n) readings saved to Health."
            } catch {
                healthResult = "Health: \(error.localizedDescription)"
            }
        }
    }

    #if DEBUG
    private func addSampleData() {
        let cal = Calendar.current
        for day in 0..<60 {
            for hour in [7, 21] {
                guard let d = cal.date(byAdding: .day, value: -day, to: cal.startOfDay(for: .now)),
                      let t = cal.date(bySettingHour: hour, minute: Int.random(in: 0...59), second: 0, of: d),
                      t <= .now else { continue }
                context.insert(Reading(date: t,
                                       systolic: Int.random(in: 125...165),
                                       diastolic: Int.random(in: 80...102),
                                       pulse: Int.random(in: 58...78),
                                       weight: 84 + Double(Int.random(in: 0...10)) / 10,
                                       drug: hour == 7))
            }
        }
        try? context.save()
    }
    #endif
}
