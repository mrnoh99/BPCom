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
    @State private var confirmDeleteAll = false
    @State private var message: String?

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
                } header: {
                    Text("Data")
                } footer: {
                    Text("\(readings.count) readings stored. CSV columns: date (yyyy-MM-dd HH:mm), systolic, diastolic, pulse, weight, drug, note, starred.")
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

                Section {
                    Button(role: .destructive) { confirmDeleteAll = true } label: {
                        Label("Delete All Readings", systemImage: "trash")
                    }
                    .disabled(readings.isEmpty)
                    #if DEBUG
                    Button { addSampleData() } label: {
                        Label("Add Sample Data (debug)", systemImage: "wand.and.stars")
                    }
                    #endif
                }

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
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .orangeNavigationBar()
            .fileExporter(isPresented: $showExporter,
                          document: exportDoc,
                          contentType: .commaSeparatedText,
                          defaultFilename: "BPCompanion-\(Date.now.formatted(.iso8601.year().month().day()))") { result in
                if case .failure(let error) = result { message = error.localizedDescription }
                else { message = "Exported \(readings.count) readings." }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
                switch result {
                case .success(let url): importCSV(url)
                case .failure(let error): message = error.localizedDescription
                }
            }
            .confirmationDialog("Delete all \(readings.count) readings?",
                                isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) {
                    for r in readings { context.delete(r) }
                    try? context.save()
                }
            } message: {
                Text(iCloudSync ? "They will also be removed from your other devices." : "This cannot be undone.")
            }
            .alert("BP Companion", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

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
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? String(decoding: data, as: UTF8.self)
            let (rows, skipped) = try CSV.parse(text)

            // Skip rows that already exist (same minute + same values).
            func key(_ d: Date, _ s: Int, _ dia: Int) -> String {
                "\(Int(d.timeIntervalSince1970 / 60))-\(s)-\(dia)"
            }
            var existing = Set(readings.map { key($0.date, $0.systolic, $0.diastolic) })
            var added = 0, duplicates = 0
            for r in rows {
                let k = key(r.date, r.systolic, r.diastolic)
                if existing.contains(k) { duplicates += 1; continue }
                existing.insert(k)
                context.insert(Reading(date: r.date, systolic: r.systolic, diastolic: r.diastolic,
                                       pulse: r.pulse, weight: r.weight, drug: r.drug,
                                       note: r.note, starred: r.starred))
                added += 1
            }
            try context.save()
            var parts = ["Imported \(added) readings."]
            if duplicates > 0 { parts.append("\(duplicates) duplicates skipped.") }
            if skipped > 0 { parts.append("\(skipped) unreadable rows skipped.") }
            message = parts.joined(separator: " ")
        } catch {
            message = "Import failed: \(error.localizedDescription)"
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
