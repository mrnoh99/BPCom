import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// CSV import / export of readings.
///
/// Format (header row required on import):
/// `date,systolic,diastolic,pulse,weight,drug,note,starred`
/// with `date` as `yyyy-MM-dd HH:mm`.
enum CSV {
    static let header = ["date", "systolic", "diastolic", "pulse", "weight", "drug", "note", "starred"]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    // MARK: Export

    static func export(_ readings: [Reading]) -> String {
        var lines = [header.joined(separator: ",")]
        for r in readings.sorted(by: { $0.date < $1.date }) {
            let fields: [String] = [
                dateFormatter.string(from: r.date),
                String(r.systolic),
                String(r.diastolic),
                String(r.pulse),
                r.weight.map { String(format: "%.1f", $0) } ?? "",
                r.drug ? "1" : "0",
                escape(r.note),
                r.starred ? "1" : "0",
            ]
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
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

        let names = head.map { $0.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "\u{FEFF}", with: "") }
        func col(_ n: String) -> Int? { names.firstIndex(of: n) }
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
                            note: value("note") ?? "",
                            starred: bool("starred")))
        }
        return (rows, skipped)
    }

    private static func parseDate(_ s: String) -> Date? {
        if let d = dateFormatter.date(from: s) { return d }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy/MM/dd HH:mm", "yyyy. M. d. HH:mm", "yyyy-MM-dd"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// RFC 4180 style record splitter (handles quotes, escaped quotes, newlines in quotes).
    private static func records(_ text: String) -> [[String]] {
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
