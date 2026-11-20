import Foundation

enum PeriodKind: String, CaseIterable, Identifiable {
    case day = "D", week = "W", month = "M", year = "Y", custom = "Custom"
    var id: String { rawValue }
}

enum TimeFilter: String, CaseIterable, Identifiable {
    case all = "All", am = "AM", pm = "PM"
    var id: String { rawValue }

    func includes(_ date: Date) -> Bool {
        switch self {
        case .all: return true
        case .am: return Calendar.current.component(.hour, from: date) < 12
        case .pm: return Calendar.current.component(.hour, from: date) >= 12
        }
    }
}

/// The From / To window shown on every Reports page.
/// D/W/M/Y windows end on `anchor` (inclusive) and are shifted with the ‹ › arrows.
struct ReportPeriod: Equatable {
    var kind: PeriodKind = .week
    var anchor: Date = Calendar.current.startOfDay(for: .now)
    var customFrom: Date = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: .now))!
    var customTo: Date = Calendar.current.startOfDay(for: .now)

    private var cal: Calendar { .current }

    /// First day (start of day) of the window.
    var from: Date {
        let end = cal.startOfDay(for: anchor)
        switch kind {
        case .day: return end
        case .week: return cal.date(byAdding: .day, value: -6, to: end)!
        case .month: return cal.date(byAdding: .day, value: 1, to: cal.date(byAdding: .month, value: -1, to: end)!)!
        case .year: return cal.date(byAdding: .day, value: 1, to: cal.date(byAdding: .year, value: -1, to: end)!)!
        case .custom: return cal.startOfDay(for: min(customFrom, customTo))
        }
    }

    /// Last day (start of day) of the window, inclusive.
    var to: Date {
        kind == .custom ? cal.startOfDay(for: max(customFrom, customTo)) : cal.startOfDay(for: anchor)
    }

    /// Exclusive upper bound.
    var end: Date { cal.date(byAdding: .day, value: 1, to: to)! }

    var dayCount: Int { (cal.dateComponents([.day], from: from, to: end).day ?? 1) }

    func contains(_ d: Date) -> Bool { d >= from && d < end }

    var canGoForward: Bool { end <= cal.startOfDay(for: .now) }

    /// The window ends today (no need for the Today button).
    var endsToday: Bool { to == cal.startOfDay(for: .now) }

    /// Reports open on the last 14 days including today (a Custom window: the arrows move
    /// it by two weeks and Today brings it back).
    static var lastTwoWeeks: ReportPeriod {
        var p = ReportPeriod()
        let today = Calendar.current.startOfDay(for: .now)
        p.setCustom(from: Calendar.current.date(byAdding: .day, value: -13, to: today)!, to: today)
        return p
    }

    /// Back to a window ending today, same length.
    mutating func goToToday() {
        let today = cal.startOfDay(for: .now)
        if kind == .custom {
            let n = dayCount
            customTo = today
            customFrom = cal.date(byAdding: .day, value: -(n - 1), to: today)!
        } else {
            anchor = today
        }
    }

    /// Custom window from the wheels or the This 2 Weeks / This Month / This Year buttons.
    mutating func setCustom(from: Date, to: Date) {
        kind = .custom
        customFrom = cal.startOfDay(for: from)
        customTo = cal.startOfDay(for: to)
    }

    mutating func shift(_ direction: Int) {
        switch kind {
        case .day: anchor = cal.date(byAdding: .day, value: direction, to: anchor)!
        case .week: anchor = cal.date(byAdding: .day, value: 7 * direction, to: anchor)!
        case .month: anchor = cal.date(byAdding: .month, value: direction, to: anchor)!
        case .year: anchor = cal.date(byAdding: .year, value: direction, to: anchor)!
        case .custom:
            let n = dayCount * direction
            customFrom = cal.date(byAdding: .day, value: n, to: from)!
            customTo = cal.date(byAdding: .day, value: n, to: to)!
        }
    }
}
