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

    @State private var exportDoc: ExportDocument?
    @State private var exportSummary = ""
    @State private var exportName = ""
    /// Backups found in iCloud Drive › BPCompanion (newest first).
    @State private var cloudBackups: [URL] = []
    @State private var showExporter = false
    @State private var showImporter = false
    /// One file picker for both imports (two .fileImporter modifiers on one view conflict).
    private enum ImportKind { case bp, yunmai, backup }
    @State private var importKind: ImportKind = .bp
    @State private var confirmDeleteImported = false
    /// Info under Export/Import: collapsed whenever Settings opens, expanded after an import/export.
    @State private var dataInfoExpanded = false
    @State private var dataResult: String?
    @State private var dataResultIsError = false

    @AppStorage(SettingsKey.healthEnabled) private var healthEnabled = true
    @AppStorage(SettingsKey.healthReadBody) private var healthReadBody = true
    @StateObject private var health = HealthSync.shared
    @Environment(\.openURL) private var openURL
    @State private var healthResult: String?
    @State private var sourcesExpanded = false
    @ObservedObject private var bodyStore = BodyStore.shared

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
                        prepareBackup()
                    } label: {
                        Label("Back Up All Data", systemImage: "externaldrive.badge.plus")
                    }
                    .disabled(readings.isEmpty && bodyStore.importedCount == 0)

                    Menu {
                        if cloudBackups.isEmpty {
                            Text("No backups in iCloud Drive › BPCompanion")
                        } else {
                            Section("iCloud Drive › BPCompanion") {
                                ForEach(cloudBackups.prefix(10), id: \.self) { url in
                                    Button(url.deletingPathExtension().lastPathComponent) {
                                        Task { await restoreFromCloud(url) }
                                    }
                                }
                            }
                        }
                        Button("Choose Another File…") {
                            importKind = .backup
                            showImporter = true
                        }
                    } label: {
                        Label("Restore from Backup", systemImage: "arrow.counterclockwise")
                    }

                    Button {
                        Task { await prepareExport() }
                    } label: {
                        Label("Export All Data (CSV)", systemImage: "square.and.arrow.up")
                    }
                    .disabled(readings.isEmpty && !bodyStore.hasAnyData)

                    Button {
                        importKind = .bp
                        showImporter = true
                    } label: {
                        Label("Import (CSV)", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        importKind = .yunmai
                        showImporter = true
                    } label: {
                        Label("Import YUNMAI Data (.imazingapp / CSV)", systemImage: "scalemass")
                    }
                    if bodyStore.importedCount > 0 {
                        Button(role: .destructive) {
                            confirmDeleteImported = true
                        } label: {
                            Label("Delete Imported YUNMAI Data (\(bodyStore.importedCount))", systemImage: "trash")
                        }
                        .confirmationDialog("Delete all imported YUNMAI weigh-ins?",
                                            isPresented: $confirmDeleteImported, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) {
                                Task {
                                    await bodyStore.deleteImported()
                                    showDataResult("Deleted the imported YUNMAI data.")
                                }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Only the history imported into BP Companion is removed (also on your other devices). Health data and the YUNMAI app are not touched.")
                        }
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
                                    Label("Send All to Health", systemImage: "arrow.up.heart")
                                    Spacer()
                                    if health.busy { ProgressView() }
                                }
                            }
                            .disabled((readings.isEmpty && bodyStore.importedCount == 0) || health.busy)
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
                        Toggle(isOn: $healthReadBody) {
                            Label("Read Body Data (YUNMAI etc.)", systemImage: "scalemass")
                        }
                        .tint(Theme.orange)
                        .onChange(of: healthReadBody) { _, on in
                            if on { Task { try? await health.requestAuthorization(); await BodyStore.shared.refresh() } }
                        }
                        if healthReadBody && !bodyStore.allSources.isEmpty {
                            DisclosureGroup("Body Data Sources", isExpanded: $sourcesExpanded) {
                                ForEach(bodyStore.allSources, id: \.self) { name in
                                    Toggle(name, isOn: Binding(
                                        get: { bodyStore.isIncluded(name) },
                                        set: { bodyStore.setIncluded(name, $0) }))
                                    .tint(Theme.orange)
                                }
                                Text("Turn off apps that are not your scale. The old “BP” app is off by default: it saved the same weight with every blood pressure reading. With iCloud Sync on, this choice is the same on your iPhone and iPad.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        if let error = health.lastError {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(Theme.high)
                        }
                    } header: {
                        Text("Apple Health")
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
                    // Shown only right after the switch is changed.
                    if iCloudSync != launchICloudSync {
                        Text("Restart the app (swipe it away and open it again) to apply this change.")
                    }
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
                    Text(AppInfo.credit)
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
                          contentType: exportDoc?.contentType ?? .json,
                          defaultFilename: exportName) { result in
                switch result {
                case .success: showDataResult(exportSummary)
                case .failure(let error): showDataResult("Export failed: \(error.localizedDescription)", error: true)
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: importKind == .bp
                            ? [.commaSeparatedText, .plainText, .text]
                            : (importKind == .backup ? [.json] : [.item])) { result in
                switch result {
                case .success(let url):
                    switch importKind {
                    case .yunmai: importYunmai(url)
                    case .backup: restoreBackup(url)
                    case .bp: importCSV(url)
                    }
                case .failure(let error): showDataResult("Import failed: \(error.localizedDescription)", error: true)
                }
            }
            .task { cloudBackups = await BackupFolder.list() }
            // Result messages appear after an action and are gone when Settings is opened again.
            .onDisappear {
                dataInfoExpanded = false
                dataResult = nil
                healthResult = nil
                sourcesExpanded = false
                health.clearMessages()
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

    /// Everything recorded so far: all blood pressure readings (BloodPressure_Data format)
    /// and all body data (imported YUNMAI history + Health), in one folder.
    private func prepareExport() async {
        await bodyStore.refresh()
        let day = Self.fileDate.string(from: .now)
        let body = CSV.exportBody()
        exportDoc = ExportDocument(.folder([
            "BloodPressure_Data_\(day).csv": CSV.export(readings),
            "Body_Data_\(day).csv": body.text,
        ]))
        exportName = "BPCompanion_Export_\(day)"
        exportSummary = "Exported \(readings.count) blood pressure readings and \(body.count) weigh-ins."
        showExporter = true
    }

    /// One JSON file with everything (readings incl. notes and stars, body records, name),
    /// for restoring after reinstalling or on a new device.
    /// Saves straight into iCloud Drive › BPCompanion (folder made if missing). If iCloud
    /// Drive is not available, lets the user choose where to save instead.
    private func prepareBackup() {
        Task {
            do {
                let b = try Backup.make(context: context)
                let name = "BPCompanion_Backup_\(Self.backupStamp.string(from: .now))"
                let summary = "Backed up \(b.readings) blood pressure readings and \(b.body) weigh-ins"
                do {
                    let url = try await BackupFolder.save(b.data, name: name)
                    showDataResult("\(summary) to iCloud Drive › BPCompanion › \(url.lastPathComponent).")
                    cloudBackups = await BackupFolder.list()
                } catch {
                    exportDoc = ExportDocument(.backup(b.data))
                    exportName = name
                    exportSummary = summary + ". (\(error.localizedDescription))"
                    showExporter = true
                }
            } catch {
                showDataResult("Backup failed: \(error.localizedDescription)", error: true)
            }
        }
    }

    private func restoreFromCloud(_ url: URL) async {
        await BackupFolder.download(url)
        restoreBackup(url)
    }

    /// yyyyMMdd_HHmm so several backups a day don't overwrite each other.
    private static let backupStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmm"
        return f
    }()

    private func restoreBackup(_ url: URL) {
        do {
            showDataResult(try Backup.restore(from: url, into: context))
            Task { await bodyStore.refresh() }
        } catch {
            showDataResult("Restore failed: \(error.localizedDescription)", error: true)
        }
    }

    private func importYunmai(_ url: URL) {
        do {
            let r = try YunmaiImport.importFile(at: url, into: context)
            showDataResult(r.message)
            Task { await bodyStore.refresh() }
        } catch {
            showDataResult("YUNMAI import failed: \(error.localizedDescription)", error: true)
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

    /// Blood pressure readings + imported YUNMAI history, without duplicates.
    private func sendAllToHealth() {
        Task {
            healthResult = await health.sendEverything(readings: readings, imported: bodyStore.imported)
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
                                       drug: hour == 7))
            }
        }
        try? context.save()
    }
    #endif
}
