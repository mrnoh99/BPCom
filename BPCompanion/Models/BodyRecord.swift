import Foundation
import SwiftData

/// One weigh-in imported from the YUNMAI app (iMazing export of its database, or the
/// CSV made from it). Holds every value the scale recorded — including the items YUNMAI
/// does not send to Apple Health (skeletal muscle, water, protein, visceral fat, bone,
/// BMR, body age). Synced to the user's other devices through iCloud like the readings.
///
/// CloudKit rules: every property has a default or is optional, no unique constraints.
@Model
final class BodyRecord {
    var id: UUID = UUID()
    var date: Date = Date()
    /// App the measurement came from, e.g. "YUNMAI".
    var source: String = "YUNMAI"

    var weight: Double?          // kg
    var bmi: Double?
    var bodyFat: Double?         // %
    var leanMass: Double?        // kg
    var skeletalMuscle: Double?  // %
    var muscle: Double?          // % (YUNMAI "Muscle" column)
    var water: Double?           // %
    var protein: Double?         // %
    var visceralFat: Double?     // level
    var boneMass: Double?        // kg
    var bmr: Double?             // kcal
    var bodyAge: Double?         // years
    var impedance: Double?       // ohm
    var height: Double?          // cm

    init(date: Date, source: String = "YUNMAI") {
        self.id = UUID()
        self.date = date
        self.source = source
    }

    /// Fat mass in kg (weight × body fat %), as the YUNMAI app shows it.
    var fatMass: Double? {
        guard let w = weight, let f = bodyFat else { return nil }
        return w * f / 100
    }

    /// Bone mass as % of weight, as the YUNMAI app shows it.
    var bonePercent: Double? {
        guard let b = boneMass, let w = weight, w > 0 else { return nil }
        return b / w * 100
    }

    /// Weigh-ins are matched by minute (Health samples and imports of the same moment).
    var minuteKey: Int { Int(date.timeIntervalSince1970 / 60) }
}
