import Foundation
import HealthKit
import SwiftUI

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

    var excludedSources: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.excludedSourcesKey) ?? Self.defaultExcludedSources) }
        set {
            UserDefaults.standard.set(Array(newValue).sorted(), forKey: Self.excludedSourcesKey)
            applyFilter()
        }
    }

    func isIncluded(_ source: String) -> Bool { !excludedSources.contains(source) }

    func setIncluded(_ source: String, _ on: Bool) {
        var s = excludedSources
        if on { s.remove(source) } else { s.insert(source) }
        excludedSources = s
    }

    private let store = HKHealthStore()
    private var observers: [HKObserverQuery] = []

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

    /// Asks for read permission once, then loads all body samples from Health.
    func refresh() async {
        guard isEnabled, !loading else { return }
        loading = true
        defer { loading = false; loaded = true }
        if !UserDefaults.standard.bool(forKey: Self.readRequestedKey) {
            try? await HealthSync.shared.requestAuthorization()
        }
        var loadedRaw: [Metric: [Sample]] = [:]
        for m in Metric.allCases {
            loadedRaw[m] = await load(m.type) { m.value(of: $0) }
        }
        raw = loadedRaw
        rawHeights = await load(HKQuantityType(.height)) { $0.doubleValue(for: .meterUnit(with: .centi)) }
        allSources = Array(Set(raw.values.flatMap { $0.map(\.source) } + rawHeights.map(\.source))).sorted()
        applyFilter()
        startObservers()
    }

    /// Drops excluded apps (e.g. "BP"), then estimates weight if none can be read.
    private func applyFilter() {
        let excluded = excludedSources
        var result = raw.mapValues { $0.filter { !excluded.contains($0.source) } }
        // A weigh-in with lean mass and body fat but no readable weight (e.g. Weight read
        // access off) gets weight = lean ÷ (1 − fat%), marked as estimated.
        let realWeights = result[.weight] ?? []
        let realKeys = Set(realWeights.map(Self.measurementKey))
        let estimates = Self.estimatedWeights(lean: result[.leanMass] ?? [], fat: result[.bodyFat] ?? [])
            .filter { !realKeys.contains(Self.measurementKey($0)) }
        result[.weight] = (realWeights + estimates).sorted { $0.date < $1.date }
        weightEstimated = realWeights.isEmpty && !estimates.isEmpty
        samples = result
        heights = rawHeights.filter { !excluded.contains($0.source) }
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
