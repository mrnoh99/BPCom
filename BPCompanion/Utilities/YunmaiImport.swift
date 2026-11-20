import Foundation
import SwiftData
import SQLite3
import Compression

/// Imports YUNMAI scale history into `BodyRecord`s from either
/// - an iMazing app export (`.imazingapp`, a zip holding `Container/Documents/xmData.sqlite`), or
/// - the CSV made from it ("Date Time","Weight (kg)","BMI","Body Fat (%)", …).
///
/// Weigh-ins already stored (same minute) are not duplicated: missing values are filled in.
enum YunmaiImport {
    struct Result {
        var added = 0
        var updated = 0
        var total = 0
        var message: String {
            var parts = ["Imported \(total) weigh-ins from YUNMAI: \(added) new"]
            if updated > 0 { parts.append("\(updated) completed") }
            return parts.joined(separator: ", ") + "."
        }
    }

    enum ImportError: LocalizedError {
        case notRecognised, noDatabase, database(String), zip(String), emptyCSV
        var errorDescription: String? {
            switch self {
            case .notRecognised: return "This file is not a YUNMAI export (.imazingapp) or YUNMAI CSV."
            case .noDatabase: return "No YUNMAI database (xmData.sqlite) was found in this file."
            case .database(let m): return "Could not read the YUNMAI database: \(m)"
            case .zip(let m): return "Could not open the file: \(m)"
            case .emptyCSV: return "The CSV has no weigh-ins."
            }
        }
    }

    /// Plain values read from a file, before merging into the store.
    struct Row {
        var date: Date
        var weight, bmi, bodyFat, leanMass, skeletalMuscle, muscle, water, protein,
            visceralFat, boneMass, bmr, bodyAge, impedance, height: Double?
    }

    /// True for files this importer understands (used by "Open in BP Companion").
    static func looksLikeYunmaiFile(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "imazingapp" { return true }
        guard let head = try? String(contentsOf: url, encoding: .utf8).prefix(400) else { return false }
        return head.contains("Weight (kg)") && !head.contains("Systolic")
    }

    @MainActor
    static func importFile(at url: URL, into context: ModelContext) throws -> Result {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)

        let rows: [Row]
        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) {          // "PK\u{3}\u{4}" = zip
            rows = try readDatabase(fromZip: data)
        } else if let text = String(data: data, encoding: .utf8), text.contains("Weight (kg)") {
            rows = try readCSV(text)
        } else {
            throw ImportError.notRecognised
        }
        return try merge(rows, into: context)
    }

    // MARK: Merge

    @MainActor
    private static func merge(_ rows: [Row], into context: ModelContext) throws -> Result {
        let existing = try context.fetch(FetchDescriptor<BodyRecord>())
        var byMinute = Dictionary(existing.map { ($0.minuteKey, $0) }, uniquingKeysWith: { a, _ in a })
        var result = Result(total: rows.count)

        for row in rows {
            let key = Int(row.date.timeIntervalSince1970 / 60)
            if let r = byMinute[key] {
                if fill(r, from: row) { result.updated += 1 }
            } else {
                let r = BodyRecord(date: row.date)
                _ = fill(r, from: row)
                context.insert(r)
                byMinute[key] = r
                result.added += 1
            }
        }
        try context.save()
        return result
    }

    /// Copies values the record does not have yet. Returns true when something changed.
    private static func fill(_ r: BodyRecord, from row: Row) -> Bool {
        var changed = false
        func set(_ kp: ReferenceWritableKeyPath<BodyRecord, Double?>, _ v: Double?) {
            guard let v, v != 0, r[keyPath: kp] == nil else { return }
            r[keyPath: kp] = v
            changed = true
        }
        set(\.weight, row.weight)
        set(\.bmi, row.bmi)
        set(\.bodyFat, row.bodyFat)
        set(\.leanMass, row.leanMass ?? leanMass(row.weight, row.bodyFat))
        set(\.skeletalMuscle, row.skeletalMuscle)
        set(\.muscle, row.muscle)
        set(\.water, row.water)
        set(\.protein, row.protein)
        set(\.visceralFat, row.visceralFat)
        set(\.boneMass, row.boneMass)
        set(\.bmr, row.bmr)
        set(\.bodyAge, row.bodyAge)
        set(\.impedance, row.impedance)
        set(\.height, row.height)
        return changed
    }

    private static func leanMass(_ w: Double?, _ f: Double?) -> Double? {
        guard let w, let f, f > 0 else { return nil }
        return (w * (1 - f / 100) * 10).rounded() / 10
    }

    // MARK: CSV

    private static func readCSV(_ text: String) throws -> [Row] {
        let table = CSV.records(text.replacingOccurrences(of: "\r\n", with: "\n"))
            .filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let head = table.first else { throw ImportError.emptyCSV }
        let names = head.map { $0.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespaces) }
        func col(_ prefix: String) -> Int? { names.firstIndex { $0.hasPrefix(prefix) } }
        guard let dateCol = col("Date") else { throw ImportError.notRecognised }

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy. M. d. HH:mm"]

        var rows: [Row] = []
        for fields in table.dropFirst() {
            func num(_ prefix: String) -> Double? {
                guard let i = col(prefix), i < fields.count else { return nil }
                return Double(fields[i].trimmingCharacters(in: .whitespaces))
            }
            guard dateCol < fields.count else { continue }
            let ds = fields[dateCol].trimmingCharacters(in: .whitespaces)
            var date: Date?
            for fmt in formats where date == nil { f.dateFormat = fmt; date = f.date(from: ds) }
            guard let date, let w = num("Weight") else { continue }
            rows.append(Row(date: date, weight: w, bmi: num("BMI"), bodyFat: num("Body Fat"),
                            leanMass: num("Lean Body Mass"), skeletalMuscle: num("Skeletal Muscle"),
                            muscle: num("Muscle (%)"), water: num("Body Water"), protein: num("Protein"),
                            visceralFat: num("Visceral Fat"), boneMass: num("Bone Mass (kg)"),
                            bmr: num("BMR"), bodyAge: num("Body Age"), impedance: num("Impedance"),
                            height: num("Height")))
        }
        guard !rows.isEmpty else { throw ImportError.emptyCSV }
        return rows
    }

    // MARK: YUNMAI SQLite database

    private static func readDatabase(fromZip data: Data) throws -> [Row] {
        let files = try ZipReader.extract(data) { name in
            let last = (name as NSString).lastPathComponent
            return last == "xmData.sqlite" || last == "xmData.sqlite-wal" || last == "xmData.sqlite-shm"
        }
        guard let db = files.first(where: { ($0.key as NSString).lastPathComponent == "xmData.sqlite" }) else {
            throw ImportError.noDatabase
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try db.value.write(to: dir.appendingPathComponent("xmData.sqlite"))
        for (name, content) in files where (name as NSString).lastPathComponent != "xmData.sqlite" {
            try content.write(to: dir.appendingPathComponent((name as NSString).lastPathComponent))
        }
        return try readRows(dbPath: dir.appendingPathComponent("xmData.sqlite").path)
    }

    private static func readRows(dbPath: String) throws -> [Row] {
        var db: OpaquePointer?
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE, nil) != SQLITE_OK {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(db)
            throw ImportError.database(message)
        }
        defer { sqlite3_close(db) }

        // Columns differ between app versions: select only those that exist.
        var columns = Set<String>()
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(WeightInfo)", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 1) {
                columns.insert(String(cString: c))
            }
        }
        sqlite3_finalize(stmt)
        guard columns.contains("Weight"), columns.contains("timeStamp") || columns.contains("CreateTime") else {
            throw ImportError.noDatabase
        }

        let wanted = ["timeStamp", "CreateTime", "Weight", "BMI", "Fat", "skeletalMuscle", "Muscle", "Water",
                      "Protein", "VisFat", "Bone", "BMR", "SomaAge", "Resistance", "heightAndAge", "Deleted"]
        let select = wanted.map { columns.contains($0) ? "\"\($0)\"" : "NULL" }.joined(separator: ", ")
        guard sqlite3_prepare_v2(db, "SELECT \(select) FROM WeightInfo", -1, &stmt, nil) == SQLITE_OK else {
            throw ImportError.database(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        local.dateFormat = "yyyy-MM-dd HH:mm:ss"

        func dbl(_ i: Int32) -> Double? {
            switch sqlite3_column_type(stmt, i) {
            case SQLITE_NULL: return nil
            case SQLITE_TEXT: return sqlite3_column_text(stmt, i).flatMap { Double(String(cString: $0)) }
            default: return sqlite3_column_double(stmt, i)
            }
        }
        func text(_ i: Int32) -> String? {
            sqlite3_column_text(stmt, i).map { String(cString: $0) }
        }

        var rows: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let deleted = dbl(15), deleted != 0 { continue }
            guard let weight = dbl(2), weight > 0 else { continue }
            // timeStamp is UTC seconds; CreateTime is the phone's local time.
            let date: Date
            if let ts = dbl(0), ts > 0 { date = Date(timeIntervalSince1970: ts) }
            else if let s = text(1), let d = local.date(from: s) { date = d }
            else { continue }
            var height: Double?
            if let json = text(14), let d = json.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                height = (obj["h"] as? NSNumber)?.doubleValue
            }
            rows.append(Row(date: date, weight: weight, bmi: dbl(3), bodyFat: dbl(4), leanMass: nil,
                            skeletalMuscle: dbl(5), muscle: dbl(6), water: dbl(7), protein: dbl(8),
                            visceralFat: dbl(9), boneMass: dbl(10), bmr: dbl(11), bodyAge: dbl(12),
                            impedance: dbl(13), height: height))
        }
        return rows
    }
}

/// Minimal zip reader (stored and deflated entries) — enough for iMazing app exports.
enum ZipReader {
    static func extract(_ data: Data, where include: (String) -> Bool) throws -> [String: Data] {
        let bytes = [UInt8](data)
        func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }

        // End of central directory record (scan back over a possible comment).
        var eocd = -1
        var i = bytes.count - 22
        while i >= max(0, bytes.count - 65_557) {
            if u32(i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw YunmaiImport.ImportError.zip("not a zip archive") }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)

        var out: [String: Data] = [:]
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(p) == 0x0201_4B50 else {
                throw YunmaiImport.ImportError.zip("damaged directory")
            }
            let method = u16(p + 10)
            let compSize = u32(p + 20), size = u32(p + 24)
            let nameLen = u16(p + 28), extraLen = u16(p + 30), commentLen = u16(p + 32)
            let localOffset = u32(p + 42)
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            p += 46 + nameLen + extraLen + commentLen

            guard include(name) else { continue }
            guard compSize != 0xFFFF_FFFF, size != 0xFFFF_FFFF else {
                throw YunmaiImport.ImportError.zip("file too large (zip64)")
            }
            guard u32(localOffset) == 0x0403_4B50 else { throw YunmaiImport.ImportError.zip("damaged entry") }
            let start = localOffset + 30 + u16(localOffset + 26) + u16(localOffset + 28)
            guard start + compSize <= bytes.count else { throw YunmaiImport.ImportError.zip("truncated entry") }
            let raw = Array(bytes[start..<(start + compSize)])

            switch method {
            case 0:
                out[name] = Data(raw)
            case 8:
                var dst = [UInt8](repeating: 0, count: max(size, 1))
                let n = compression_decode_buffer(&dst, dst.count, raw, raw.count, nil, COMPRESSION_ZLIB)
                guard n == size else { throw YunmaiImport.ImportError.zip("could not decompress \(name)") }
                out[name] = Data(dst.prefix(n))
            default:
                throw YunmaiImport.ImportError.zip("unsupported compression")
            }
        }
        return out
    }
}
