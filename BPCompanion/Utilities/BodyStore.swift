import Foundation
import HealthKit
import SwiftUI
import SwiftData

/// Body composition read from Apple Health — weight, BMI, body fat, lean body mass and height —
/// as written by a smart scale app such as YUNMAI. Kept separate from the blood-pressure
/// readings: nothing here is entered in BP Companion or attached to a reading.
@MainActor
final class BodyStore: ObservableObject {
    static let shared = BodyStore()

    enum Metric: String, CaseIterable, Identifiable {
        case weight, bmi, bodyFat, leanMass
        var id: String { rawValue }

        var title: String {
            switch self {
            case .weight: return "Weight"
            case .bmi: return "BMI"
            case .bodyFat: return "Body Fat"
            case .leanMass: return "Lean Mass"
            }
        }
        var unit: String {
            switch self {
            case .weight, .leanMass: return "kg"
            case .bmi: return ""
            case .bodyFat: return "%"
            }
        }
        var type: HKQuantityType {
            switch self {
            case .weight: return HKQuantityType(.bodyMass)
            case .bmi: return HKQuantityType(.bodyMassIndex)
            case .bodyFat: return HKQuantityType(.bodyFatPercentage)
            case .leanMass: return HKQuantityType(.leanBodyMass)
            }
        }
        var color: Color {
            switch self {
            case .weight: return Theme.weightLine
            case .bmi: return Theme.systolicLine
            case .bodyFat: return Theme.orange
            case .leanMass: return Theme.diastolicLine
            }
        }
        /// Value in display units (kg, BMI, % 0–100).
        func value(of q: HKQuantity) -> Double {
            switch self {
            case .weight, .leanMass: return q.doubleValue(for: .gramUnit(with: .kilo))
            case .bmi: return q.doubleValue(for: .count())
            case .bodyFat: return q.doubleValue(for: .percent()) * 100
            }
        }
        func format(_ v: Double) -> String { String(format: "%.1f", v) }
    }

    struct Sample: Identifiable {
        let id: UUID
        let date: Date
        let value: Double
        let source: String
        /// Weight worked out from lean mass and body fat (Weight itself not readable).
        var estimated = false
    }

    static let readTypes: Set<HKObjectType> =
        Set(Metric.allCases.map { $0.type as HKObjectType }).union([HKQuantityType(.height)])
    /// Bumped when a type is added (v2: height), so the permission sheet asks for it once.
    static let readRequestedKey = "healthBodyReadRequested.v2"

    @Published private(set) var samples: [Metric: [Sample]] = [:]
    /// Height in cm (YUNMAI writes it too). Shown in the Body tab; it rarely changes,
    /// so it is not part of the period analysis.
    @Published private(set) var heights: [Sample] = []
    @Published private(set) var loaded = false
    @Published private(set) var loading = false

    /// Everything read from Health, before the source filter.
    private var raw: [Metric: [Sample]] = [:]
    private var rawHeights: [Sample] = []
    /// Every app that has written body data, including excluded ones (Settings list).
    @Published private(set) var allSources: [String] = []

    /// Apps whose body data is left out. Default: "BP" — the old blood-pressure app,
    /// which saved a fixed weight with every reading; it is not scale data.
    static let excludedSourcesKey = "bodyExcludedSources"
    static let defaultExcludedSources = ["BP"]

    /// Kept in iCloud key-value storage (when iCloud Sync is on) so iPhone and iPad
    /// use the same choice, with a local copy in UserDefaults for offline / sync off.
    var excludedSources: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.excludedSourcesKey) ?? Self.defaultExcludedSources) }
        set {
            let list = Array(newValue).sorted()
            UserDefaults.standard.set(list, forKey: Self.excludedSourcesKey)
            if Self.cloudSyncOn {
                NSUbiquitousKeyValueStore.default.set(list, forKey: Self.excludedSourcesKey)
                NSUbiquitousKeyValueStore.default.synchronize()
            }
            sourceChoiceVersion += 1
            applyFilter()
        }
    }

    /// Bumped when the source choice changes (here or on the other device) to refresh views.
    @Published private(set) var sourceChoiceVersion = 0

    private static var cloudSyncOn: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.iCloudSync) as? Bool ?? true
    }

    private init() {
        guard Self.cloudSyncOn else { return }
        let kvs = NSUbiquitousKeyValueStore.default
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.pullCloudChoice() }
            }
        kvs.synchronize()
        if kvs.array(forKey: Self.excludedSourcesKey) == nil,
           let local = UserDefaults.standard.stringArray(forKey: Self.excludedSourcesKey) {
            // First device to run this version: publish its choice to iCloud.
            kvs.set(local, forKey: Self.excludedSourcesKey)
            kvs.synchronize()
        } else {
            pullCloudChoice()
        }
    }

    /// The other device changed the choice: take it over locally and re-filter.
    private func pullCloudChoice() {
        guard let list = NSUbiquitousKeyValueStore.default.array(forKey: Self.excludedSourcesKey) as? [String] else { return }
        guard list.sorted() != (UserDefaults.standard.stringArray(forKey: Self.excludedSourcesKey) ?? []).sorted() else { return }
        UserDefaults.standard.set(list, forKey: Self.excludedSourcesKey)
        sourceChoiceVersion += 1
        applyFilter()
    }

    func isIncluded(_ source: String) -> Bool { !excludedSources.contains(source) }

    func setIncluded(_ source: String, _ on: Bool) {
        var s = excludedSources
        if on { s.remove(source) } else { s.insert(source) }
        excludedSources = s
    }

    private let store = HKHealthStore()
    private var observers: [HKObserverQuery] = []

    // MARK: Imported YUNMAI history (BodyRecord, synced with iCloud)

    /// Value copy of a `BodyRecord`.
    struct Imported: Identifiable {
        let id: UUID
        let date: Date
        let source: String
        let weight, bmi, bodyFat, leanMass, skeletalMuscle, muscle, water, protein,
            visceralFat, boneMass, bmr, bodyAge, height: Double?
        var fatMass: Double? { weight.flatMap { w in bodyFat.map { w * $0 / 100 } } }
        var bonePercent: Double? {
            guard let b = boneMass, let w = weight, w > 0 else { return nil }
            return b / w * 100
        }
        /// True when it carries the items Health does not have.
        var hasExtras: Bool { [skeletalMuscle, water, protein, visceralFat, boneMass, bmr, bodyAge].contains { $0 != nil } }

        init(_ r: BodyRecord) {
            id = r.id; date = r.date; source = r.source
            weight = r.weight; bmi = r.bmi; bodyFat = r.bodyFat; leanMass = r.leanMass
            skeletalMuscle = r.skeletalMuscle; muscle = r.muscle; water = r.water; protein = r.protein
            visceralFat = r.visceralFat; boneMass = r.boneMass; bmr = r.bmr; bodyAge = r.bodyAge
            height = r.height
        }
    }

    private var context: ModelContext?
    @Published private(set) var imported: [Imported] = []
    private var extrasByMinute: [Int: Imported] = [:]

    /// Gives the store access to the SwiftData container (imported records).
    func attach(_ context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
    }

    /// Minutes that already have this metric in Health from any app (before filtering),
    /// so imported weigh-ins are not written to Health twice.
    func healthMinutes(_ m: Metric) -> Set<Int> {
        Set((raw[m] ?? []).map { Self.minute($0.date) })
    }

    var healthHeightMinutes: Set<Int> { Set(rawHeights.map { Self.minute($0.date) }) }

    /// Imported record of the same minute (for skeletal muscle, water, …).
    func extra(at date: Date) -> Imported? { extrasByMinute[Self.minute(date)] }

    var importedCount: Int { imported.count }

    static func minute(_ d: Date) -> Int { Int(d.timeIntervalSince1970 / 60) }

    private func loadImported() {
        guard let context else { return }
        let all = (try? context.fetch(FetchDescriptor<BodyRecord>(sortBy: [SortDescriptor(\.date)]))) ?? []
        imported = all.map(Imported.init)
    }

    /// Removes every imported YUNMAI record (Health data is not touched).
    func deleteImported() async {
        guard let context else { return }
        for r in (try? context.fetch(FetchDescriptor<BodyRecord>())) ?? [] { context.delete(r) }
        try? context.save()
        await refresh()
    }

    /// Anything to show (Health or imported).
    var hasAnyData: Bool {
        !samples.values.allSatisfy { $0.isEmpty } || !heights.isEmpty
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var isEnabled: Bool { isAvailable && UserDefaults.standard.bool(forKey: SettingsKey.healthReadBody) }

    /// Source apps currently shown (e.g. "YUNMAI").
    var sources: [String] {
        Array(Set(samples.values.flatMap { $0.map(\.source) } + heights.map(\.source))).sorted()
    }

    func latest(_ m: Metric, source: String? = nil) -> Sample? {
        samples[m]?.last { source == nil || $0.source == source }
    }

    /// BMI / fat / lean arrive but no weight at all: Health returns nothing (no error)
    /// when read access to Weight is off, so this is almost always that permission.
    var weightAccessLikelyOff: Bool { weightEstimated }

    /// True when no weight could be read and the weights shown are estimates.
    @Published private(set) var weightEstimated = false

    func latestHeight(source: String? = nil) -> Sample? {
        heights.last { source == nil || $0.source == source }
    }

    // MARK: Loading

    /// Loads imported YUNMAI records, then (when Health is on) asks for read permission
    /// once and loads all body samples from Health.
    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false; loaded = true }
        loadImported()
        if isEnabled {
            if !UserDefaults.standard.bool(forKey: Self.readRequestedKey) {
                try? await HealthSync.shared.requestAuthorization()
            }
            var loadedRaw: [Metric: [Sample]] = [:]
            for m in Metric.allCases {
                loadedRaw[m] = await load(m.type) { m.value(of: $0) }
            }
            raw = loadedRaw
            rawHeights = await load(HKQuantityType(.height)) { $0.doubleValue(for: .meterUnit(with: .centi)) }
        } else {
            raw = [:]
            rawHeights = []
        }
        allSources = Array(Set(raw.values.flatMap { $0.map(\.source) } + rawHeights.map(\.source)
                               + imported.map(\.source))).sorted()
        applyFilter()
        if isEnabled { startObservers() }
    }

    /// Drops excluded apps (e.g. "BP"), then estimates weight if none can be read.
    private func applyFilter() {
        let excluded = excludedSources
        var result = raw.mapValues { $0.filter { !excluded.contains($0.source) } }

        // Imported YUNMAI weigh-ins fill in what Health doesn't have (same minute = same
        // weigh-in, Health's value kept), e.g. the years YUNMAI never sent to Health.
        let imp = imported.filter { !excluded.contains($0.source) }
        extrasByMinute = Dictionary(imp.map { (Self.minute($0.date), $0) }, uniquingKeysWith: { a, _ in a })
        func addImported(_ m: Metric, _ value: (Imported) -> Double?) {
            let have = Set((result[m] ?? []).map { Self.minute($0.date) })
            let more = imp.compactMap { r -> Sample? in
                guard let v = value(r), !have.contains(Self.minute(r.date)) else { return nil }
                return Sample(id: r.id, date: r.date, value: v, source: r.source)
            }
            if !more.isEmpty { result[m] = ((result[m] ?? []) + more).sorted { $0.date < $1.date } }
        }
        addImported(.weight) { $0.weight }
        addImported(.bmi) { $0.bmi }
        addImported(.bodyFat) { $0.bodyFat }
        addImported(.leanMass) { $0.leanMass }
        // A weigh-in with lean mass and body fat but no readable weight (e.g. Weight read
        // access off) gets weight = lean ÷ (1 − fat%), marked as estimated.
        let realWeights = result[.weight] ?? []
        let realKeys = Set(realWeights.map(Self.measurementKey))
        let estimates = Self.estimatedWeights(lean: result[.leanMass] ?? [], fat: result[.bodyFat] ?? [])
            .filter { !realKeys.contains(Self.measurementKey($0)) }
        result[.weight] = (realWeights + estimates).sorted { $0.date < $1.date }
        weightEstimated = realWeights.isEmpty && !estimates.isEmpty
        samples = result
        let healthHeights = rawHeights.filter { !excluded.contains($0.source) }
        let haveH = Set(healthHeights.map { Self.minute($0.date) })
        let importedHeights = imp.compactMap { r -> Sample? in
            guard let h = r.height, !haveH.contains(Self.minute(r.date)) else { return nil }
            return Sample(id: r.id, date: r.date, value: h, source: r.source)
        }
        heights = (healthHeights + importedHeights).sorted { $0.date < $1.date }
    }

    private func load(_ type: HKQuantityType, value: @escaping (HKQuantity) -> Double) async -> [Sample] {
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        let found: [HKSample] = await withCheckedContinuation { c in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: sort) { _, s, _ in c.resume(returning: s ?? []) }
            store.execute(q)
        }
        return found.compactMap { s in
            guard let q = s as? HKQuantitySample, !Self.isFromBPCompanion(q) else { return nil }
            return Sample(id: q.uuid, date: q.startDate, value: value(q.quantity),
                          source: q.sourceRevision.source.name)
        }
    }

    /// Reloads while the app is open when the scale app writes a new measurement.
    private func startObservers() {
        guard observers.isEmpty else { return }
        for m in Metric.allCases {
            let q = HKObserverQuery(sampleType: m.type, predicate: nil) { [weak self] _, done, _ in
                Task { @MainActor in await self?.refresh() }
                done()
            }
            store.execute(q)
            observers.append(q)
        }
    }

    /// Weight from lean body mass and body fat % measured at the same minute by the same app.
    /// Values of one weigh-in share the source app and the minute.
    static func measurementKey(_ s: Sample) -> String {
        "\(s.source)|\(Int(s.date.timeIntervalSince1970 / 60))"
    }

    static func estimatedWeights(lean: [Sample], fat: [Sample]) -> [Sample] {
        let fatByKey = Dictionary(fat.map { (measurementKey($0), $0.value) }, uniquingKeysWith: { a, _ in a })
        return lean.compactMap { l in
            guard let f = fatByKey[measurementKey(l)], f > 0, f < 90 else { return nil }
            let w = (l.value / (1 - f / 100) * 10).rounded() / 10
            return Sample(id: UUID(), date: l.date, value: w, source: l.source, estimated: true)
        }
    }

    /// Samples BP Companion wrote itself (older versions saved weight to Health) are not
    /// scale data and are left out — matched by bundle ID, by the reading-ID metadata
    /// every BP Companion sample carries, and by app name (an earlier build may have had
    /// another bundle ID).
    static func isFromBPCompanion(_ s: HKSample) -> Bool {
        let source = s.sourceRevision.source
        if source.bundleIdentifier == Bundle.main.bundleIdentifier { return true }
        if s.metadata?[HealthSync.readingKey] != nil { return true }
        let ownName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "BP Companion"
        return source.name == ownName || source.name.localizedCaseInsensitiveContains("BP Companion")
    }

    // MARK: Analysis helpers

    /// Korean Society for the Study of Obesity cut-offs (Asian BMI criteria).
    static func bmiCategory(_ bmi: Double) -> (String, Color) {
        switch bmi {
        case ..<18.5: return ("Underweight", Theme.low)
        case ..<23: return ("Normal", Theme.normal)
        case ..<25: return ("Overweight", Theme.elevated)
        case ..<30: return ("Obese (class 1)", Theme.high)
        default: return ("Obese (class 2+)", Theme.high)
        }
    }
}
