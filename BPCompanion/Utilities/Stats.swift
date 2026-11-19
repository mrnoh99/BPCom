import Foundation

struct Aggregate {
    var max: Double
    var min: Double
    var avg: Double

    init?(_ values: [Double]) {
        guard let mx = values.max(), let mn = values.min() else { return nil }
        max = mx
        min = mn
        avg = values.reduce(0, +) / Double(values.count)
    }
}

/// MAX / MIN / AVG for every metric of a set of readings.
struct ReadingStats {
    let count: Int
    let systolic: Aggregate?
    let diastolic: Aggregate?
    let pulse: Aggregate?
    let map: Aggregate?

    init(_ readings: [Reading]) {
        count = readings.count
        systolic = Aggregate(readings.map { Double($0.systolic) })
        diastolic = Aggregate(readings.map { Double($0.diastolic) })
        pulse = Aggregate(readings.map { Double($0.pulse) })
        map = Aggregate(readings.map { $0.map })
    }
}

enum Fmt {
    static func int(_ v: Double) -> String { String(Int(v.rounded())) }
    static func weight(_ v: Double) -> String { String(format: "%.1f", v) }
    static func percent(_ v: Double) -> String { String(format: "%.1f %%", v) }

    static func date(_ d: Date) -> String { d.formatted(date: .numeric, time: .omitted) }
    static func dateTime(_ d: Date) -> String { d.formatted(date: .numeric, time: .shortened) }
    static func time(_ d: Date) -> String { timeFormatter.string(from: d) }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    static func month(_ d: Date) -> String { d.formatted(.dateTime.year().month(.wide)) }
}

enum AppInfo {
    /// "1.0 (8)" — marketing version and build number from the bundle.
    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    /// "Developed by Jaisung NOH MD 2026 · Version 1.0 (8)"
    static var credit: String { "Developed by Jaisung NOH MD 2026 · Version \(version)" }
}
