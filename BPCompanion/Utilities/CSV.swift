import Foundation
import SwiftUI
import UniformTypeIdentifiers
import SwiftData

/// CSV import / export of readings.
///
/// Export format (same as the "BloodPressure_Data" files of the previous app):
/// ```
/// "Date Time","Period","Systolic (mmHg)","Diastolic (mmHg)","MAP (mmHg)","Heart Rate (bpm)","Weight (kg)","Drug","Note"
/// "2026. 11. 19. 06:54","Morning","141","95","110","66","84.5","YES",""
/// ```
/// Every field is quoted, newest reading first, UTF-8, `\n` line endings.
/// Import accepts this format and the older `date,systolic,diastolic,...` format.
enum CSV {
    static let header = ["Date Time", "Period", "Systolic (mmHg)", "Diastolic (mmHg)", "MAP (mmHg)",
                         "Heart Rate (bpm)", "Weight (kg)", "Drug", "Note"]

    /// "2026. 11. 19. 06:54"
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy. M. d. HH:mm"
        return f
    }()

    /// Morning 04:00–11:59, Day 12:00–17:59, Evening 18:00–03:59
    static func period(of date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<12: return "Morning"
        case 12..<18: return "Day"
        default: return "Evening"
        }
    }

    // MARK: Export

    static func export(_ readings: [Reading]) -> String {
        var lines = [header.map(quote).joined(separator: ",")]
        for r in readings.sorted(by: { $0.date > $1.date }) {
            let fields: [String] = [
                dateFormatter.string(from: r.date),
                period(of: r.date),
                String(r.systolic),
                String(r.diastolic),
                String(Int(r.map.rounded())),
                String(r.pulse),
                r.weight.map { String(format: "%.1f", $0) } ?? "",
                r.drug ? "YES" : "NO",
                r.note,
            ]
            lines.append(fields.map(quote).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: Import

    struct Row {
        var date: Date
        var systolic: Int
        var diastolic: Int
        var pulse: Int
        var weight: Double?
        var drug: Bool
        var note: String
        var starred: Bool
    }

    enum ImportError: LocalizedError {
        case missingColumns([String])
        case empty

        var errorDescription: String? {
            switch self {
            case .missingColumns(let c): return "Missing column(s): \(c.joined(separator: ", "))"
            case .empty: return "The file contains no data."
            }
        }
    }

    /// Parses CSV text. Rows that cannot be read are skipped and counted.
    static func parse(_ text: String) throws -> (rows: [Row], skipped: Int) {
        var table = records(text.replacingOccurrences(of: "\r\n", with: "\n"))
        table.removeAll { $0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let head = table.first else { throw ImportError.empty }

        let names = head.map(normalize)
        func col(_ n: String) -> Int? {
            for alias in aliases[n] ?? [n] {
                if let i = names.firstIndex(of: alias) { return i }
            }
            return nil
        }
        let required = ["date", "systolic", "diastolic"]
        let missing = required.filter { col($0) == nil }
        guard missing.isEmpty else { throw ImportError.missingColumns(missing) }

        var rows: [Row] = []
        var skipped = 0
        for fields in table.dropFirst() {
            func value(_ n: String) -> String? {
                guard let i = col(n), i < fields.count else { return nil }
                let v = fields[i].trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
            func bool(_ n: String) -> Bool {
                guard let v = value(n)?.lowercased() else { return false }
                return ["1", "true", "yes", "y", "o"].contains(v)
            }
            guard let ds = value("date"), let date = parseDate(ds),
                  let s = value("systolic").flatMap(Int.init),
                  let d = value("diastolic").flatMap(Int.init) else {
                skipped += 1
                continue
            }
            rows.append(Row(date: date,
                            systolic: s,
                            diastolic: d,
                            pulse: value("pulse").flatMap(Int.init) ?? 0,
                            weight: value("weight").flatMap(Double.init),
                            drug: bool("drug"),
                            note: col("note").flatMap { $0 < fields.count ? fields[$0] : nil } ?? "",   // kept verbatim
                            starred: bool("starred")))
        }
        return (rows, skipped)
    }

    /// Column name → accepted header spellings (after `normalize`).
    private static let aliases: [String: [String]] = [
        "date": ["date time", "date", "datetime", "date/time"],
        "systolic": ["systolic", "sys", "sbp"],
        "diastolic": ["diastolic", "dia", "dbp"],
        "pulse": ["heart rate", "pulse", "hr", "bpm"],
        "weight": ["weight"],
        "drug": ["drug", "medication"],
        "note": ["note", "notes", "memo"],
        "starred": ["starred", "star"],
    ]

    /// "Systolic (mmHg)" → "systolic"
    private static func normalize(_ h: String) -> String {
        var s = h.replacingOccurrences(of: "\u{FEFF}", with: "")
        if let i = s.firstIndex(of: "(") { s = String(s[..<i]) }
        return s.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func parseDate(_ s: String) -> Date? {
        if let d = dateFormatter.date(from: s) { return d }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy/MM/dd HH:mm", "yyyy. M. d. HH:mm:ss", "yyyy-MM-dd"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// RFC 4180 style record splitter (handles quotes, escaped quotes, newlines in quotes).
    static func records(_ text: String) -> [[String]] {
        var result: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var it = Array(text)
        it.append("\n")
        var i = 0
        while i < it.count {
            let c = it[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < it.count, it[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r":
                    row.append(field); field = ""
                    result.append(row); row = []
                default: field.append(c)
                }
            }
            i += 1
        }
        return result
    }
}

/// Wrapper so `.fileExporter` can write the CSV text.
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Imports a CSV file (BloodPressure_Data format or the older format) into the store.
/// Used by Settings › Import and by opening a .csv file with the app (Files, Mail, share sheet).
enum CSVImporter {
    /// Returns a user-facing summary, e.g. "Imported 485 readings."
    @MainActor
    static func importFile(at url: URL, into context: ModelContext) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let text: String
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let utf16 = String(data: data, encoding: .utf16) {
            text = utf16                                                  // Excel "Unicode text"
        } else {
            text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .init(rawValue: 0x80000422)) // CP949/EUC-KR (Korean Excel)
                ?? String(decoding: data, as: UTF8.self)
        }
        let (rows, skipped) = try CSV.parse(text)

        // Skip rows that already exist (same minute + same BP and pulse).
        func key(_ d: Date, _ s: Int, _ dia: Int, _ p: Int) -> String {
            "\(Int(d.timeIntervalSince1970 / 60))-\(s)-\(dia)-\(p)"
        }
        let existingReadings = try context.fetch(FetchDescriptor<Reading>())
        var existing = Set(existingReadings.map { key($0.date, $0.systolic, $0.diastolic, $0.pulse) })
        var added = 0, duplicates = 0
        var inserted: [Reading] = []
        for r in rows {
            let k = key(r.date, r.systolic, r.diastolic, r.pulse)
            if existing.contains(k) { duplicates += 1; continue }
            existing.insert(k)
            let reading = Reading(date: r.date, systolic: r.systolic, diastolic: r.diastolic,
                                  pulse: r.pulse, weight: r.weight, drug: r.drug,
                                  note: r.note, starred: r.starred)
            context.insert(reading)
            inserted.append(reading)
            added += 1
        }
        try context.save()
        HealthSync.shared.upsert(inserted)

        var parts = ["Imported \(added) readings."]
        if duplicates > 0 { parts.append("\(duplicates) duplicates skipped.") }
        if skipped > 0 { parts.append("\(skipped) unreadable rows skipped.") }
        return parts.joined(separator: " ")
    }
}

// MARK: - Body data export

extension CSV {
    /// Every weigh-in shown in the app (Health + imported YUNMAI history), newest first,
    /// with all items. Same columns as the YUNMAI CSV, so it can be imported again.
    @MainActor
    static func exportBody() -> (text: String, count: Int) {
        let store = BodyStore.shared
        let items = WeightHistoryList.measurements(from: store.samples, extra: store.extra(at:))
        let heightByMinute = Dictionary(store.heights.map { (BodyStore.minute($0.date), $0.value) },
                                        uniquingKeysWith: { a, _ in a })
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"

        func n(_ v: Double?, _ digits: Int = 1) -> String {
            guard let v, v != 0 else { return "" }
            return String(format: "%.\(digits)f", v)
        }
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

        let header = ["Date Time", "Weight (kg)", "BMI", "Body Fat (%)", "Fat Mass (kg)", "Lean Body Mass (kg)",
                      "Skeletal Muscle (%)", "Muscle (%)", "Body Water (%)", "Protein (%)", "Visceral Fat (level)",
                      "Bone Mass (kg)", "Bone Mass (%)", "BMR (kcal)", "Body Age", "Height (cm)", "Weight Estimated",
                      "Source"]
        var lines = [header.map(q).joined(separator: ",")]
        for m in items {
            let x = m.extra
            let fatMass = m.weight.flatMap { w in m.bodyFat.map { w * $0 / 100 } }
            let height = x?.height ?? heightByMinute[BodyStore.minute(m.date)]
            let fields = [
                f.string(from: m.date), n(m.weight, 2), n(m.bmi), n(m.bodyFat), n(fatMass), n(m.leanMass),
                n(x?.skeletalMuscle), n(x?.muscle), n(x?.water), n(x?.protein), n(x?.visceralFat, 0),
                n(x?.boneMass), n(x?.bonePercent), n(x?.bmr, 0), n(x?.bodyAge, 0), n(height),
                m.weightEstimated ? "YES" : "", m.source,
            ]
            lines.append(fields.map(q).joined(separator: ","))
        }
        return (lines.joined(separator: "\n"), items.count)
    }
}

/// "Export All Data": a folder with the blood pressure CSV and the body data CSV.
struct ExportFolder: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }
    var files: [String: String]   // file name → CSV text

    init(files: [String: String]) { self.files = files }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        var wrappers: [String: FileWrapper] = [:]
        for (name, text) in files {
            let w = FileWrapper(regularFileWithContents: Data(text.utf8))
            w.preferredFilename = name
            wrappers[name] = w
        }
        return FileWrapper(directoryWithFileWrappers: wrappers)
    }
}
