import Foundation
import HealthKit
import SwiftData

/// Writes readings to the Apple Health app:
/// blood pressure (systolic/diastolic correlation) and heart rate.
/// (Body weight is not written: it comes from the scale app and is read by `BodyStore`.)
///
/// Every sample carries `HKMetadataKeySyncIdentifier` derived from the reading's UUID,
/// so writing the same reading again (an edit, "Send All", or another device that
/// received the reading through iCloud) replaces the earlier copy instead of duplicating it.
@MainActor
final class HealthSync: ObservableObject {
    static let shared = HealthSync()

    /// Custom metadata key holding the reading's UUID (used to delete a reading's samples).
    static let readingKey = "BPCompanionReadingID"

    let store = HKHealthStore()

    @Published private(set) var busy = false
    /// Last error from writing to Health (shown in Settings).
    @Published private(set) var lastError: String?
    /// Bumped after an authorization request so views re-read `access`.
    @Published private(set) var accessChecked = 0

    private var didAutoConnect = false
    private static let initialSyncDoneKey = "healthInitialSyncDone"

    enum Access { case unavailable, notAsked, allowed, denied }

    var access: Access {
        guard isAvailable else { return .unavailable }
        switch store.authorizationStatus(for: HKQuantityType(.bloodPressureSystolic)) {
        case .notDetermined: return .notAsked
        case .sharingAuthorized: return .allowed
        default: return .denied
        }
    }

    /// Health data is unavailable on Mac ("Designed for iPad") and some iPads.
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// The user turned on "Write to Health" in Settings.
    var isEnabled: Bool {
        isAvailable && UserDefaults.standard.bool(forKey: SettingsKey.healthEnabled)
    }

    private var quantityTypes: [HKQuantityType] {
        [HKQuantityType(.bloodPressureSystolic), HKQuantityType(.bloodPressureDiastolic),
         HKQuantityType(.heartRate)]
    }

    /// True when the user allowed writing blood pressure in the Health permission sheet.
    var isAuthorized: Bool {
        isAvailable && store.authorizationStatus(for: HKQuantityType(.bloodPressureSystolic)) == .sharingAuthorized
    }

    // MARK: Authorization

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthError.unavailable }
        // Write: BP and heart rate (when "Write to Health" is on).
        // Read: weight, BMI, body fat, lean mass (when "Read Body Data" is on) — e.g. YUNMAI.
        let share: Set<HKSampleType> = UserDefaults.standard.bool(forKey: SettingsKey.healthEnabled)
            ? Set(quantityTypes) : []
        let read: Set<HKObjectType> = UserDefaults.standard.bool(forKey: SettingsKey.healthReadBody)
            ? BodyStore.readTypes : []
        guard !share.isEmpty || !read.isEmpty else { return }
        defer { accessChecked += 1 }
        do {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                store.requestAuthorization(toShare: share, read: read) { _, error in
                    if let error { c.resume(throwing: error) } else { c.resume() }
                }
            }
            if !read.isEmpty { UserDefaults.standard.set(true, forKey: BodyStore.readRequestedKey) }
        } catch {
            // Typically "Missing com.apple.developer.healthkit entitlement" when the
            // HealthKit capability is not enabled for the signing team / App ID.
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Called when the app becomes active. The first time, it shows the Health permission
    /// sheet (that is what makes "BP Companion" appear in Health › Sharing › Apps /
    /// Data Sources) and then copies all existing readings to Health once.
    func autoConnectIfNeeded(_ context: ModelContext) async {
        guard isEnabled, !didAutoConnect else { return }
        didAutoConnect = true
        if access == .notAsked { try? await requestAuthorization() }
        guard access == .allowed,
              !UserDefaults.standard.bool(forKey: Self.initialSyncDoneKey) else { return }
        let readings = (try? context.fetch(FetchDescriptor<Reading>())) ?? []
        guard !readings.isEmpty else { return }   // wait until there is data (e.g. from iCloud)
        if (try? await sendAll(readings)) != nil {
            UserDefaults.standard.set(true, forKey: Self.initialSyncDoneKey)
        }
    }

    /// App became active: permission (first time, write + body read together) → copy
    /// readings → load body data. One after another, so the permission sheet shows once.
    func onBecameActive(_ context: ModelContext) async {
        await autoConnectIfNeeded(context)
        await BodyStore.shared.refresh()
    }

    // MARK: Writing

    /// Value copy of a reading, safe to use after the SwiftData object changes.
    struct Snapshot {
        let id: String
        let date: Date
        let systolic: Int
        let diastolic: Int
        let pulse: Int

        init(_ r: Reading) {
            id = r.id.uuidString
            date = r.date
            systolic = r.systolic
            diastolic = r.diastolic
            pulse = r.pulse
        }
    }

    /// Adds or updates readings in Health (no-op when the user has not enabled it).
    func upsert(_ readings: [Reading]) {
        guard isEnabled, !readings.isEmpty else { return }
        let snaps = readings.map(Snapshot.init)
        Task {
            do { try await write(snaps); lastError = nil }
            catch { lastError = error.localizedDescription }
        }
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
        lastError = nil
        defer { busy = false }
        // Write in chunks so very large histories don't hit a single huge transaction.
        var start = 0
        while start < snaps.count {
            let end = min(start + 200, snaps.count)
            do {
                try await write(Array(snaps[start..<end]))
            } catch {
                lastError = error.localizedDescription
                throw error
            }
            start = end
        }
        return snaps.count
    }

    private func write(_ snaps: [Snapshot]) async throws {
        // Remove old samples first so a cleared pulse doesn't linger after an edit.
        try? await delete(snaps.map(\.id))

        // Only types the user allowed: Health rejects the whole save ("Not authorized")
        // if any one sample's type is not allowed.
        let bpAllowed = canWrite(.bloodPressureSystolic) && canWrite(.bloodPressureDiastolic)
        let hrAllowed = canWrite(.heartRate)
        let version = Int(Date().timeIntervalSince1970)
        var objects: [HKObject] = []
        for s in snaps {
            objects.append(contentsOf: samples(for: s, version: version, bp: bpAllowed, hr: hrAllowed))
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

    func canWrite(_ id: HKQuantityTypeIdentifier) -> Bool {
        store.authorizationStatus(for: HKQuantityType(id)) == .sharingAuthorized
    }

    private func samples(for s: Snapshot, version: Int, bp: Bool, hr: Bool) -> [HKObject] {
        func meta(_ suffix: String) -> [String: Any] {
            [HKMetadataKeySyncIdentifier: "\(s.id).\(suffix)",
             HKMetadataKeySyncVersion: version,
             HKMetadataKeyWasUserEntered: true,
             Self.readingKey: s.id]
        }
        let mmHg = HKUnit.millimeterOfMercury()
        var out: [HKObject] = []

        if bp {
            let sys = HKQuantitySample(type: HKQuantityType(.bloodPressureSystolic),
                                       quantity: HKQuantity(unit: mmHg, doubleValue: Double(s.systolic)),
                                       start: s.date, end: s.date, metadata: meta("sys"))
            let dia = HKQuantitySample(type: HKQuantityType(.bloodPressureDiastolic),
                                       quantity: HKQuantity(unit: mmHg, doubleValue: Double(s.diastolic)),
                                       start: s.date, end: s.date, metadata: meta("dia"))
            out.append(HKCorrelation(type: HKCorrelationType(.bloodPressure),
                                     start: s.date, end: s.date,
                                     objects: [sys, dia], metadata: meta("bp")))
        }

        if hr && s.pulse > 0 {
            out.append(HKQuantitySample(type: HKQuantityType(.heartRate),
                                        quantity: HKQuantity(unit: .count().unitDivided(by: .minute()),
                                                             doubleValue: Double(s.pulse)),
                                        start: s.date, end: s.date, metadata: meta("hr")))
        }
        return out
    }

    /// Asks only for reading Weight. Shows the Health sheet when Weight read was never
    /// requested (it then appears in Health › Sharing › Apps › BP Companion).
    func requestWeightRead() async throws {
        guard isAvailable else { throw HealthError.unavailable }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: nil, read: [HKQuantityType(.bodyMass)]) { _, error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            }
        }
        accessChecked += 1
    }

    // MARK: Apple Watch heart rate

    struct WatchPulse {
        let bpm: Int
        let date: Date
    }

    /// Latest heart rate measured by an Apple Watch within the last `minutes` (from Health).
    /// Values written by BP Companion or other apps (e.g. the old BP app) are ignored.
    /// The first call asks for read access to Heart Rate.
    func latestWatchPulse(within minutes: Int = 10) async -> WatchPulse? {
        guard isAvailable else { return nil }
        let type = HKQuantityType(.heartRate)
        if !UserDefaults.standard.bool(forKey: Self.heartRateReadRequestedKey) {
            let ok: Bool = await withCheckedContinuation { c in
                store.requestAuthorization(toShare: nil, read: [type]) { success, _ in c.resume(returning: success) }
            }
            if ok { UserDefaults.standard.set(true, forKey: Self.heartRateReadRequestedKey) }
        }
        let since = Date().addingTimeInterval(-Double(minutes) * 60)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        let found: [HKSample] = await withCheckedContinuation { c in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 50,
                                  sortDescriptors: sort) { _, s, _ in c.resume(returning: s ?? []) }
            store.execute(q)
        }
        for s in found {
            guard let q = s as? HKQuantitySample, !BodyStore.isFromBPCompanion(q),
                  Self.isFromAppleWatch(q) else { continue }
            let bpm = q.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
            return WatchPulse(bpm: Int(bpm.rounded()), date: q.endDate)
        }
        return nil
    }

    static let heartRateReadRequestedKey = "healthHeartRateReadRequested"

    /// Heart rate recorded by an Apple Watch (device model "Watch", or a Watch product type).
    static func isFromAppleWatch(_ s: HKSample) -> Bool {
        if s.device?.model?.localizedCaseInsensitiveContains("watch") == true { return true }
        if s.sourceRevision.productType?.hasPrefix("Watch") == true { return true }
        return false
    }

    // MARK: Imported YUNMAI history → Health

    /// Writes imported YUNMAI weigh-ins to Health (weight, BMI, body fat, lean mass, height)
    /// for the minutes Health does not already have. Each sample has a sync identifier
    /// ("yunmai.<minute>.<type>"), so sending again replaces instead of duplicating.
    /// Returns the number of weigh-ins written.
    func sendImportedBody(_ records: [BodyStore.Imported]) async throws -> Int {
        guard isAvailable else { throw HealthError.unavailable }

        // What Health already has (YUNMAI's own samples, from any device).
        let body = BodyStore.shared
        await body.refresh()
        let have: [BodyStore.Metric: Set<Int>] = Dictionary(uniqueKeysWithValues:
            BodyStore.Metric.allCases.map { ($0, body.healthMinutes($0)) })
        let haveHeight = body.healthHeightMinutes

        var objects: [HKObject] = []
        var written = 0
        for r in records {
            let minute = BodyStore.minute(r.date)
            var wroteAny = false
            func add(_ type: HKQuantityType, _ unit: HKUnit, _ value: Double?, _ tag: String, skip: Bool) {
                guard let value, value > 0, !skip,
                      store.authorizationStatus(for: type) == .sharingAuthorized else { return }
                let meta: [String: Any] = [HKMetadataKeySyncIdentifier: "yunmai.\(minute).\(tag)",
                                           HKMetadataKeySyncVersion: 1,
                                           "BPCompanionImportedFrom": r.source]
                objects.append(HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value),
                                                start: r.date, end: r.date, metadata: meta))
                wroteAny = true
            }
            add(HKQuantityType(.bodyMass), .gramUnit(with: .kilo), r.weight, "kg",
                skip: have[.weight]?.contains(minute) == true)
            add(HKQuantityType(.bodyMassIndex), .count(), r.bmi, "bmi",
                skip: have[.bmi]?.contains(minute) == true)
            add(HKQuantityType(.bodyFatPercentage), .percent(), r.bodyFat.map { $0 / 100 }, "fat",
                skip: have[.bodyFat]?.contains(minute) == true)
            add(HKQuantityType(.leanBodyMass), .gramUnit(with: .kilo), r.leanMass, "lean",
                skip: have[.leanMass]?.contains(minute) == true)
            add(HKQuantityType(.height), .meterUnit(with: .centi), r.height, "cm",
                skip: haveHeight.contains(minute))
            if wroteAny { written += 1 }
        }

        busy = true
        defer { busy = false }
        var start = 0
        while start < objects.count {
            let chunk = Array(objects[start..<min(start + 500, objects.count)])
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                store.save(chunk) { _, error in
                    if let error { c.resume(throwing: error) } else { c.resume() }
                }
            }
            start += 500
        }
        return written
    }

    // MARK: Send everything

    /// Every type "Send All to Health" writes, with the names Health shows.
    private static let sendTypes: [(HKQuantityTypeIdentifier, String)] = [
        (.bloodPressureSystolic, "Blood Pressure"), (.bloodPressureDiastolic, "Blood Pressure"),
        (.heartRate, "Heart Rate"), (.bodyMass, "Weight"), (.bodyMassIndex, "Body Mass Index"),
        (.bodyFatPercentage, "Body Fat Percentage"), (.leanBodyMass, "Lean Body Mass"), (.height, "Height"),
    ]

    /// "Send All to Health": blood pressure readings and the imported YUNMAI history.
    /// Asks write permission for every type first, writes only the allowed ones (no
    /// "Not authorized" for the whole batch), skips weigh-ins Health already has and
    /// replaces earlier copies by sync identifier — so nothing is duplicated.
    /// Returns a message for Settings.
    func sendEverything(readings: [Reading], imported: [BodyStore.Imported]) async -> String {
        guard isAvailable else { return HealthError.unavailable.localizedDescription }
        let share = Set(Self.sendTypes.map { HKQuantityType($0.0) as HKSampleType })
        var read = BodyStore.readTypes
        read.insert(HKQuantityType(.heartRate))
        do {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                store.requestAuthorization(toShare: share, read: read) { _, error in
                    if let error { c.resume(throwing: error) } else { c.resume() }
                }
            }
        } catch {
            return "Health: \(error.localizedDescription)"
        }
        accessChecked += 1

        var parts: [String] = []
        do {
            if !readings.isEmpty, canWrite(.bloodPressureSystolic) || canWrite(.heartRate) {
                let n = try await sendAll(readings)
                parts.append("\(n) blood pressure readings")
            }
            if !imported.isEmpty {
                let n = try await sendImportedBody(imported)
                parts.append("\(n) new YUNMAI weigh-ins")
            }
        } catch {
            return "Health: \(error.localizedDescription)"
        }

        var message = parts.isEmpty ? "Nothing was sent." : "Sent to Health: " + parts.joined(separator: ", ") + "."
        let denied = Array(Set(Self.sendTypes.filter { !canWrite($0.0) }.map(\.1))).sorted()
        if !denied.isEmpty {
            message += " Not allowed, so skipped: \(denied.joined(separator: ", ")). Turn them on in Health › Sharing › Apps › BP Companion (iPad: Settings › Health › Data Access & Devices)."
        }
        return message
    }

    enum HealthError: LocalizedError {
        case unavailable, notAllowed
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Apple Health is not available on this device."
            case .notAllowed: return "Writing weight to Health was not allowed. Turn it on in Health › Sharing › Apps › BP Companion."
            }
        }
    }
}
