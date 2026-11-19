import Foundation
import HealthKit

/// Writes readings to the Apple Health app:
/// blood pressure (systolic/diastolic correlation), heart rate and body weight.
///
/// Every sample carries `HKMetadataKeySyncIdentifier` derived from the reading's UUID,
/// so writing the same reading again (an edit, "Send All", or another device that
/// received the reading through iCloud) replaces the earlier copy instead of duplicating it.
@MainActor
final class HealthSync: ObservableObject {
    static let shared = HealthSync()

    /// Custom metadata key holding the reading's UUID (used to delete a reading's samples).
    static let readingKey = "BPCompanionReadingID"

    private let store = HKHealthStore()

    @Published private(set) var busy = false

    /// Health data is unavailable on Mac ("Designed for iPad") and some iPads.
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// The user turned on "Write to Health" in Settings.
    var isEnabled: Bool {
        isAvailable && UserDefaults.standard.bool(forKey: SettingsKey.healthEnabled)
    }

    private var quantityTypes: [HKQuantityType] {
        [HKQuantityType(.bloodPressureSystolic), HKQuantityType(.bloodPressureDiastolic),
         HKQuantityType(.heartRate), HKQuantityType(.bodyMass)]
    }

    /// True when the user allowed writing blood pressure in the Health permission sheet.
    var isAuthorized: Bool {
        isAvailable && store.authorizationStatus(for: HKQuantityType(.bloodPressureSystolic)) == .sharingAuthorized
    }

    // MARK: Authorization

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthError.unavailable }
        let types = Set<HKSampleType>(quantityTypes)
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: types, read: nil) { _, error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            }
        }
    }

    // MARK: Writing

    /// Value copy of a reading, safe to use after the SwiftData object changes.
    struct Snapshot {
        let id: String
        let date: Date
        let systolic: Int
        let diastolic: Int
        let pulse: Int
        let weight: Double?

        init(_ r: Reading) {
            id = r.id.uuidString
            date = r.date
            systolic = r.systolic
            diastolic = r.diastolic
            pulse = r.pulse
            weight = r.weight
        }
    }

    /// Adds or updates readings in Health (no-op when the user has not enabled it).
    func upsert(_ readings: [Reading]) {
        guard isEnabled, !readings.isEmpty else { return }
        let snaps = readings.map(Snapshot.init)
        Task { try? await write(snaps) }
    }

    /// Removes deleted readings from Health (no-op when not enabled).
    func remove(ids: [UUID]) {
        guard isEnabled, !ids.isEmpty else { return }
        let strings = ids.map(\.uuidString)
        Task { try? await delete(strings) }
    }

    /// Writes every reading (used when Health is turned on and by "Send All to Health").
    /// Returns the number of readings written.
    func sendAll(_ readings: [Reading]) async throws -> Int {
        guard isAvailable else { throw HealthError.unavailable }
        let snaps = readings.map(Snapshot.init)
        busy = true
        defer { busy = false }
        // Write in chunks so very large histories don't hit a single huge transaction.
        var start = 0
        while start < snaps.count {
            let end = min(start + 200, snaps.count)
            try await write(Array(snaps[start..<end]))
            start = end
        }
        return snaps.count
    }

    private func write(_ snaps: [Snapshot]) async throws {
        // Remove old samples first so a cleared weight / pulse doesn't linger after an edit.
        try? await delete(snaps.map(\.id))

        let version = Int(Date().timeIntervalSince1970)
        var objects: [HKObject] = []
        for s in snaps {
            objects.append(contentsOf: samples(for: s, version: version))
        }
        guard !objects.isEmpty else { return }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            store.save(objects) { _, error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            }
        }
    }

    private func delete(_ ids: [String]) async throws {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: Self.readingKey, allowedValues: ids)
        var types: [HKObjectType] = quantityTypes
        types.append(HKCorrelationType(.bloodPressure))
        for type in types {
            try? await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                store.deleteObjects(of: type, predicate: predicate) { _, _, error in
                    if let error { c.resume(throwing: error) } else { c.resume() }
                }
            }
        }
    }

    private func samples(for s: Snapshot, version: Int) -> [HKObject] {
        func meta(_ suffix: String) -> [String: Any] {
            [HKMetadataKeySyncIdentifier: "\(s.id).\(suffix)",
             HKMetadataKeySyncVersion: version,
             HKMetadataKeyWasUserEntered: true,
             Self.readingKey: s.id]
        }
        let mmHg = HKUnit.millimeterOfMercury()
        var out: [HKObject] = []

        let sys = HKQuantitySample(type: HKQuantityType(.bloodPressureSystolic),
                                   quantity: HKQuantity(unit: mmHg, doubleValue: Double(s.systolic)),
                                   start: s.date, end: s.date, metadata: meta("sys"))
        let dia = HKQuantitySample(type: HKQuantityType(.bloodPressureDiastolic),
                                   quantity: HKQuantity(unit: mmHg, doubleValue: Double(s.diastolic)),
                                   start: s.date, end: s.date, metadata: meta("dia"))
        out.append(HKCorrelation(type: HKCorrelationType(.bloodPressure),
                                 start: s.date, end: s.date,
                                 objects: [sys, dia], metadata: meta("bp")))

        if s.pulse > 0 {
            out.append(HKQuantitySample(type: HKQuantityType(.heartRate),
                                        quantity: HKQuantity(unit: .count().unitDivided(by: .minute()),
                                                             doubleValue: Double(s.pulse)),
                                        start: s.date, end: s.date, metadata: meta("hr")))
        }
        if let w = s.weight {
            out.append(HKQuantitySample(type: HKQuantityType(.bodyMass),
                                        quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: w),
                                        start: s.date, end: s.date, metadata: meta("kg")))
        }
        return out
    }

    enum HealthError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Apple Health is not available on this device." }
    }
}
