import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Full backup of everything BP Companion stores — every blood pressure reading (with
/// note and star) and every imported body record (all YUNMAI items) — in one JSON file,
/// for restoring after reinstalling or on a new device. Restoring merges: nothing that is
/// already there is duplicated.
enum Backup {
    struct File: Codable {
        var app = "BP Companion"
        var format = 1
        var created: Date
        var ownerName: String?
        var readings: [ReadingItem]
        var bodyRecords: [BodyItem]
    }

    struct ReadingItem: Codable {
        var id: UUID
        var date: Date
        var systolic: Int
        var diastolic: Int
        var pulse: Int
        var weight: Double?
        var drug: Bool
        var note: String
        var starred: Bool
    }

    struct BodyItem: Codable {
        var id: UUID
        var date: Date
        var source: String
        var weight, bmi, bodyFat, leanMass, skeletalMuscle, muscle, water, protein,
            visceralFat, boneMass, bmr, bodyAge, impedance, height: Double?
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: Back up

    @MainActor
    static func make(context: ModelContext) throws -> (data: Data, readings: Int, body: Int) {
        let readings = try context.fetch(FetchDescriptor<Reading>(sortBy: [SortDescriptor(\.date)]))
        let records = try context.fetch(FetchDescriptor<BodyRecord>(sortBy: [SortDescriptor(\.date)]))
        let file = File(
            created: .now,
            ownerName: UserDefaults.standard.string(forKey: SettingsKey.ownerName),
            readings: readings.map {
                ReadingItem(id: $0.id, date: $0.date, systolic: $0.systolic, diastolic: $0.diastolic,
                            pulse: $0.pulse, weight: $0.weight, drug: $0.drug, note: $0.note,
                            starred: $0.starred)
            },
            bodyRecords: records.map {
                BodyItem(id: $0.id, date: $0.date, source: $0.source, weight: $0.weight, bmi: $0.bmi,
                         bodyFat: $0.bodyFat, leanMass: $0.leanMass, skeletalMuscle: $0.skeletalMuscle,
                         muscle: $0.muscle, water: $0.water, protein: $0.protein,
                         visceralFat: $0.visceralFat, boneMass: $0.boneMass, bmr: $0.bmr,
                         bodyAge: $0.bodyAge, impedance: $0.impedance, height: $0.height)
            })
        return (try encoder.encode(file), readings.count, records.count)
    }

    // MARK: Restore

    enum RestoreError: LocalizedError {
        case notBackup
        var errorDescription: String? { "This file is not a BP Companion backup." }
    }

    @MainActor
    static func restore(from url: URL, into context: ModelContext) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let file = try? decoder.decode(File.self, from: data), file.app == "BP Companion" else {
            throw RestoreError.notBackup
        }

        // Readings: skip ones already present (same id, or same minute and values).
        let existing = try context.fetch(FetchDescriptor<Reading>())
        var ids = Set(existing.map(\.id))
        func key(_ d: Date, _ s: Int, _ dia: Int, _ p: Int) -> String {
            "\(Int(d.timeIntervalSince1970 / 60))-\(s)-\(dia)-\(p)"
        }
        var keys = Set(existing.map { key($0.date, $0.systolic, $0.diastolic, $0.pulse) })
        var added: [Reading] = []
        for item in file.readings {
            let k = key(item.date, item.systolic, item.diastolic, item.pulse)
            guard !ids.contains(item.id), !keys.contains(k) else { continue }
            let r = Reading(date: item.date, systolic: item.systolic, diastolic: item.diastolic,
                            pulse: item.pulse, weight: item.weight, drug: item.drug,
                            note: item.note, starred: item.starred)
            r.id = item.id
            context.insert(r)
            added.append(r)
            ids.insert(item.id)
            keys.insert(k)
        }

        // Body records: same minute = same weigh-in; fill in values that are missing.
        let bodies = try context.fetch(FetchDescriptor<BodyRecord>())
        var byMinute = Dictionary(bodies.map { ($0.minuteKey, $0) }, uniquingKeysWith: { a, _ in a })
        var bodyAdded = 0
        for item in file.bodyRecords {
            let minute = Int(item.date.timeIntervalSince1970 / 60)
            let r: BodyRecord
            if let found = byMinute[minute] {
                r = found
            } else {
                r = BodyRecord(date: item.date, source: item.source)
                r.id = item.id
                context.insert(r)
                byMinute[minute] = r
                bodyAdded += 1
            }
            func fill(_ kp: ReferenceWritableKeyPath<BodyRecord, Double?>, _ v: Double?) {
                if r[keyPath: kp] == nil, let v { r[keyPath: kp] = v }
            }
            fill(\.weight, item.weight); fill(\.bmi, item.bmi); fill(\.bodyFat, item.bodyFat)
            fill(\.leanMass, item.leanMass); fill(\.skeletalMuscle, item.skeletalMuscle)
            fill(\.muscle, item.muscle); fill(\.water, item.water); fill(\.protein, item.protein)
            fill(\.visceralFat, item.visceralFat); fill(\.boneMass, item.boneMass); fill(\.bmr, item.bmr)
            fill(\.bodyAge, item.bodyAge); fill(\.impedance, item.impedance); fill(\.height, item.height)
        }
        try context.save()

        // Name: take the backup's when this install still has the default.
        if let name = file.ownerName, !name.isEmpty,
           (UserDefaults.standard.string(forKey: SettingsKey.ownerName) ?? SettingsKey.defaultOwnerName)
            == SettingsKey.defaultOwnerName {
            UserDefaults.standard.set(name, forKey: SettingsKey.ownerName)
        }

        HealthSync.shared.upsert(added)
        let skipped = file.readings.count - added.count
        var msg = "Restored \(added.count) blood pressure readings and \(bodyAdded) weigh-ins"
        msg += " from the backup of \(file.created.formatted(date: .abbreviated, time: .shortened))."
        if skipped > 0 { msg += " \(skipped) readings were already here." }
        return msg
    }
}

/// The app's own folder in iCloud Drive ("iCloud Drive › BPCompanion"), created
/// automatically and visible in the Files app. Backups are saved here directly.
enum BackupFolder {
    enum FolderError: LocalizedError {
        case iCloudUnavailable
        var errorDescription: String? {
            "iCloud Drive is not available. Sign in to iCloud and turn on iCloud Drive for BP Companion in Settings › [your name] › iCloud."
        }
    }

    /// iCloud Drive › BPCompanion (the container's Documents folder). Created if missing.
    /// Looked up off the main thread, as Apple requires.
    static func url() async -> URL? {
        let id = CloudSyncMonitor.containerID
        return await Task.detached {
            guard let root = FileManager.default.url(forUbiquityContainerIdentifier: id) else { return nil }
            let docs = root.appendingPathComponent("Documents", isDirectory: true)
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            return docs
        }.value
    }

    /// Writes the backup into iCloud Drive › BPCompanion and returns its URL.
    static func save(_ data: Data, name: String) async throws -> URL {
        guard let dir = await url() else { throw FolderError.iCloudUnavailable }
        let file = dir.appendingPathComponent(name).appendingPathExtension("json")
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordError) { u in
            do { try data.write(to: u, options: .atomic) } catch { writeError = error }
        }
        if let e = coordError ?? writeError { throw e }
        return file
    }

    /// Backups in the folder, newest first (also ones still only in iCloud).
    static func list() async -> [URL] {
        guard let dir = await url() else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let files = names.compactMap { name -> URL? in
            // Not yet downloaded: ".BPCompanion_Backup_x.json.icloud"
            var n = name
            if n.hasPrefix("."), n.hasSuffix(".icloud") { n = String(n.dropFirst().dropLast(7)) }
            guard n.hasPrefix("BPCompanion_Backup"), n.hasSuffix(".json") else { return nil }
            return dir.appendingPathComponent(n)
        }
        return Array(Set(files)).sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Makes sure an iCloud file is on this device before reading it (waits up to ~15 s).
    static func download(_ file: URL) async {
        if FileManager.default.fileExists(atPath: file.path) { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: file)
        for _ in 0..<30 {
            if FileManager.default.fileExists(atPath: file.path) { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}

/// What Settings › Data saves: the backup (.json) or the CSV folder.
struct ExportDocument: FileDocument {
    enum Content {
        case backup(Data)
        case folder([String: String])   // file name → CSV text
    }

    static var readableContentTypes: [UTType] { [.json, .folder] }
    var content: Content

    init(_ content: Content) { self.content = content }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    var contentType: UTType {
        if case .backup = content { return .json }
        return .folder
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        switch content {
        case .backup(let data):
            return FileWrapper(regularFileWithContents: data)
        case .folder(let files):
            var wrappers: [String: FileWrapper] = [:]
            for (name, text) in files {
                let w = FileWrapper(regularFileWithContents: Data(text.utf8))
                w.preferredFilename = name
                wrappers[name] = w
            }
            return FileWrapper(directoryWithFileWrappers: wrappers)
        }
    }
}
