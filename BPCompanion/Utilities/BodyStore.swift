import Foundation
import HealthKit
import SwiftUI

/// Body composition read from Apple Health — weight, BMI, body fat and lean body mass —
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
    }

    static let readTypes: Set<HKObjectType> = Set(Metric.allCases.map { $0.type as HKObjectType })
    static let readRequestedKey = "healthBodyReadRequested"

    @Published private(set) var samples: [Metric: [Sample]] = [:]
    @Published private(set) var loaded = false
    @Published private(set) var loading = false

    private let store = HKHealthStore()
    private var observers: [HKObserverQuery] = []

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var isEnabled: Bool { isAvailable && UserDefaults.standard.bool(forKey: SettingsKey.healthReadBody) }

    /// Every source app that has written body data (e.g. "YUNMAI").
    var sources: [String] {
        Array(Set(samples.values.flatMap { $0.map(\.source) })).sorted()
    }

    func latest(_ m: Metric, source: String? = nil) -> Sample? {
        samples[m]?.last { source == nil || $0.source == source }
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
        var result: [Metric: [Sample]] = [:]
        for m in Metric.allCases {
            result[m] = await load(m)
        }
        samples = result
        startObservers()
    }

    private func load(_ m: Metric) async -> [Sample] {
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        let found: [HKSample] = await withCheckedContinuation { c in
            let q = HKSampleQuery(sampleType: m.type, predicate: nil, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: sort) { _, s, _ in c.resume(returning: s ?? []) }
            store.execute(q)
        }
        let own = Bundle.main.bundleIdentifier
        return found.compactMap { s in
            guard let q = s as? HKQuantitySample,
                  q.sourceRevision.source.bundleIdentifier != own else { return nil }
            return Sample(id: q.uuid, date: q.startDate, value: m.value(of: q.quantity),
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
