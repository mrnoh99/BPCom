import Foundation
import SwiftData

/// One blood-pressure measurement.
///
/// Every stored property has a default value (or is optional) and there are no
/// unique constraints, which is what SwiftData requires for CloudKit (iCloud) sync.
@Model
final class Reading {
    var id: UUID = UUID()
    var date: Date = Date()
    var systolic: Int = 120
    var diastolic: Int = 80
    var pulse: Int = 70
    /// Legacy: body weight in kg kept only for the CSV "Weight (kg)" column.
    /// Not entered or shown in the app — body data comes from Apple Health (Body tab).
    var weight: Double?
    var drug: Bool = false
    var note: String = ""
    var starred: Bool = false

    init(date: Date = .now,
         systolic: Int,
         diastolic: Int,
         pulse: Int,
         weight: Double? = nil,
         drug: Bool = false,
         note: String = "",
         starred: Bool = false) {
        self.id = UUID()
        self.date = date
        self.systolic = systolic
        self.diastolic = diastolic
        self.pulse = pulse
        self.weight = weight
        self.drug = drug
        self.note = note
        self.starred = starred
    }

    /// Mean arterial pressure: DBP + (SBP − DBP) / 3
    var map: Double { BP.map(systolic: systolic, diastolic: diastolic) }

    var systolicLevel: BPLevel { BPLevel.systolic(systolic) }
    var diastolicLevel: BPLevel { BPLevel.diastolic(diastolic) }
}

enum BP {
    static func map(systolic: Int, diastolic: Int) -> Double {
        Double(diastolic) + Double(systolic - diastolic) / 3.0
    }
}

/// Classification used for value colours and the Range report.
enum BPLevel: Int, CaseIterable {
    case low, normal, elevated, high

    static func systolic(_ v: Int) -> BPLevel {
        switch v {
        case ..<90: return .low
        case 90...119: return .normal
        case 120...139: return .elevated
        default: return .high
        }
    }

    static func diastolic(_ v: Int) -> BPLevel {
        switch v {
        case ..<60: return .low
        case 60...79: return .normal
        case 80...89: return .elevated
        default: return .high
        }
    }

    static func systolic(_ v: Double) -> BPLevel { systolic(Int(v.rounded())) }
    static func diastolic(_ v: Double) -> BPLevel { diastolic(Int(v.rounded())) }
}
