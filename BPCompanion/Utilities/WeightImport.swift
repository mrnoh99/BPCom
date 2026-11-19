import Foundation
import HealthKit
import SwiftData

/// Brings body weight measured by another app (e.g. the YUNMAI scale app, which writes
/// to Apple Health) into blood-pressure readings.
///
/// Rules
/// - Only weight samples from other apps are used (BP Companion's own samples are ignored).
/// - A weight sample goes to the reading of the same day that is closest in time.
/// - Each sample is used at most once (its Health UUID is stored on the reading), and a
///   reading gets at most one weight, so several BP readings in a day get the weight once,
///   and several weigh-ins in a day each go to their nearest reading without repeating.
/// - A reading that already has a weight (typed in, or imported before, or one the user
///   cleared after import) is never overwritten; the sample nearest to it is then skipped.
extension HealthSync {
    struct WeightSample: Equatable {
        let id: String
        let date: Date
        let kg: Double
        let source: String
    }

    var isWeightImportEnabled: Bool {
        isAvailable && UserDefaults.standard.bool(forKey: SettingsKey.healthImportWeight)
    }

    // MARK: Reading Health

    /// Weight samples written by other apps between `start` and `end`.
    func externalWeights(from start: Date, to end: Date) async -> [WeightSample] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        let results: [HKSample] = await withCheckedContinuation { c in
            let query = HKSampleQuery(sampleType: HKQuantityType(.bodyMass), predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: sort) { _, samples, _ in
                c.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
        let ownBundle = Bundle.main.bundleIdentifier
        return results.compactMap { sample in
            guard let q = sample as? HKQuantitySample,
                  q.sourceRevision.source.bundleIdentifier != ownBundle,
                  q.metadata?[Self.readingKey] == nil else { return nil }
            let kg = (q.quantity.doubleValue(for: .gramUnit(with: .kilo)) * 10).rounded() / 10
            return WeightSample(id: q.uuid.uuidString, date: q.startDate, kg: kg,
                                source: q.sourceRevision.source.name)
        }
    }

    /// Shows the Health permission sheet for reading weight once (if not asked before).
    func requestWeightReadIfNeeded() async {
        guard isWeightImportEnabled,
              !UserDefaults.standard.bool(forKey: Self.weightReadRequestedKey) else { return }
        try? await requestAuthorization()
    }

    // MARK: Matching

    /// For each reading index, the weight sample assigned to it: every sample picks the
    /// closest reading of the same day, and a reading keeps the closest of the samples
    /// that picked it.
    nonisolated static func match(readingDates: [Date], samples: [WeightSample]) -> [Int: WeightSample] {
        let cal = Calendar.current
        var best: [Int: (sample: WeightSample, distance: TimeInterval)] = [:]
        for s in samples {
            var nearest: (index: Int, distance: TimeInterval)?
            for (i, d) in readingDates.enumerated() where cal.isDate(d, inSameDayAs: s.date) {
                let distance = abs(d.timeIntervalSince(s.date))
                if nearest == nil || distance < nearest!.distance { nearest = (i, distance) }
            }
            guard let n = nearest else { continue }
            if best[n.index] == nil || n.distance < best[n.index]!.distance {
                best[n.index] = (s, n.distance)
            }
        }
        return best.mapValues(\.sample)
    }

    // MARK: Importing

    /// Fills in weight from Health for readings between `start` and `end`.
    /// Returns the number of readings that received a weight.
    @discardableResult
    func importWeights(from start: Date, to end: Date, context: ModelContext) async -> Int {
        guard isWeightImportEnabled else { return 0 }
        await requestWeightReadIfNeeded()
        let samples = await externalWeights(from: start, to: end)
        guard !samples.isEmpty else { return 0 }

        let descriptor = FetchDescriptor<Reading>(predicate: #Predicate { $0.date >= start && $0.date < end })
        guard let readings = try? context.fetch(descriptor), !readings.isEmpty else { return 0 }

        let used = Set(readings.compactMap(\.weightSourceID))
        let unused = samples.filter { !used.contains($0.id) }
        var count = 0
        for (index, sample) in Self.match(readingDates: readings.map(\.date), samples: unused) {
            let r = readings[index]
            guard r.weight == nil, r.weightSourceID == nil else { continue }   // never overwrite
            r.weight = sample.kg
            r.weightSourceID = sample.id
            r.weightSourceName = sample.source
            count += 1
        }
        if count > 0 { try? context.save() }
        return count
    }

    /// Today's weigh-ins → today's readings. Runs when the app becomes active, after a
    /// reading is saved and whenever Health reports a new weight while the app is open.
    @discardableResult
    func importTodayWeights(_ context: ModelContext) async -> Int {
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return await importWeights(from: start, to: end, context: context)
    }

    /// Weight to pre-fill in the Add Entry screen for a new reading at `date` (today only):
    /// the unused weigh-in of today whose nearest reading would be this new one.
    func suggestedWeight(at date: Date, context: ModelContext) async -> WeightSample? {
        guard isWeightImportEnabled, Calendar.current.isDateInToday(date) else { return nil }
        await requestWeightReadIfNeeded()
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let samples = await externalWeights(from: start, to: end)
        guard !samples.isEmpty else { return nil }
        let descriptor = FetchDescriptor<Reading>(predicate: #Predicate { $0.date >= start && $0.date < end })
        let readings = (try? context.fetch(descriptor)) ?? []
        let used = Set(readings.compactMap(\.weightSourceID))
        var dates = readings.map(\.date)
        dates.append(date)
        return Self.match(readingDates: dates, samples: samples.filter { !used.contains($0.id) })[dates.count - 1]
    }

    /// Re-runs today's import whenever Health gets a new weight while the app is open.
    func startWeightObserver(_ context: ModelContext) {
        guard isWeightImportEnabled, weightObserver == nil else { return }
        let query = HKObserverQuery(sampleType: HKQuantityType(.bodyMass), predicate: nil) { [weak self] _, done, _ in
            Task { @MainActor in
                await self?.importTodayWeights(context)
            }
            done()
        }
        store.execute(query)
        weightObserver = query
    }
}
