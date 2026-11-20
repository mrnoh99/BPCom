import SwiftUI

/// History › Weight: every weigh-in from Apple Health (e.g. the YUNMAI scale) and from the
/// imported YUNMAI history, newest first, grouped by month. Read-only.
struct WeightHistoryList: View {
    @ObservedObject private var bodyStore = BodyStore.shared
    @AppStorage(SettingsKey.healthReadBody) private var readBody = true
    @State private var collapsed: Set<String> = []

    /// One weigh-in: the values the scale app wrote at the same moment.
    struct Measurement: Identifiable {
        let id: String
        let date: Date
        let source: String
        var weight: Double?
        var weightEstimated = false
        var bmi: Double?
        var bodyFat: Double?
        var leanMass: Double?
        /// Weight change from the previous weigh-in (kg).
        var change: Double?
        /// Imported YUNMAI record of the same minute (skeletal muscle, water, …).
        var extra: BodyStore.Imported?
    }

    private struct MonthSection: Identifiable {
        let id: String
        let title: String
        let items: [Measurement]
    }

    private var measurements: [Measurement] {
        Self.measurements(from: bodyStore.samples, extra: bodyStore.extra(at:))
    }

    /// Joins the separate samples (weight, BMI, fat, lean) of one weigh-in by minute —
    /// not by app name, which differs for the same scale ("윈마이" in Health, "YUNMAI"
    /// when imported) — newest first. Also used by the Body tab's history.
    static func measurements(from samples: [BodyStore.Metric: [BodyStore.Sample]],
                             extra: (Date) -> BodyStore.Imported? = { _ in nil }) -> [Measurement] {
        var byKey: [String: Measurement] = [:]
        for m in BodyStore.Metric.allCases {
            for s in samples[m] ?? [] {
                let minute = Int(s.date.timeIntervalSince1970 / 60)
                let key = "\(minute)"
                var item = byKey[key] ?? Measurement(id: key, date: s.date, source: s.source)
                switch m {
                case .weight: item.weight = s.value; item.weightEstimated = s.estimated
                case .bmi: item.bmi = s.value
                case .bodyFat: item.bodyFat = s.value
                case .leanMass: item.leanMass = s.value
                }
                byKey[key] = item
            }
        }
        var list = byKey.values.sorted { $0.date < $1.date }
        for i in list.indices { list[i].extra = extra(list[i].date) }
        var previous: Double?
        for i in list.indices {
            if let w = list[i].weight {
                if let previous { list[i].change = w - previous }
                previous = w
            }
        }
        return list.reversed()
    }

    private var sections: [MonthSection] {
        let cal = Calendar.current
        var order: [String] = []
        var groups: [String: [Measurement]] = [:]
        var titles: [String: String] = [:]
        for m in measurements {
            let c = cal.dateComponents([.year, .month], from: m.date)
            let key = String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
            if groups[key] == nil {
                order.append(key)
                titles[key] = Fmt.month(m.date)
            }
            groups[key, default: []].append(m)
        }
        return order.map { MonthSection(id: $0, title: titles[$0] ?? $0, items: groups[$0] ?? []) }
    }

    var body: some View {
        Group {
            if bodyStore.loaded && measurements.isEmpty {
                BodyEmptyState()
            } else {
                list
            }
        }
        .task { await bodyStore.refresh() }
    }

    private var list: some View {
        List {
            if bodyStore.weightAccessLikelyOff {
                WeightAccessHint()
                    .listRowBackground(Theme.background)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .listRowSeparator(.hidden)
            }
            ForEach(sections) { section in
                Section {
                    if !collapsed.contains(section.id) {
                        ForEach(section.items) { m in
                            WeightRow(m: m)
                                .listRowBackground(Theme.background)
                                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                                .listRowSeparatorTint(Theme.gridLine)
                        }
                    }
                } header: {
                    Button {
                        withAnimation {
                            if collapsed.contains(section.id) { collapsed.remove(section.id) }
                            else { collapsed.insert(section.id) }
                        }
                    } label: {
                        HStack {
                            Text(section.title)
                            Text("· \(section.items.count)")
                                .foregroundStyle(Theme.secondaryText)
                            Spacer()
                            Image(systemName: collapsed.contains(section.id) ? "chevron.right" : "chevron.down")
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(Theme.cellHeader)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .noTopScrollBlur()
        .readableWidth(900)
        .refreshable { await bodyStore.refresh() }
    }

    private func empty(_ title: String, _ message: String) -> some View {
        ContentUnavailableView(title, systemImage: "scalemass", description: Text(message))
            .frame(maxHeight: .infinity)
    }
}

struct WeightRow: View {
    let m: WeightHistoryList.Measurement

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CalendarBadge(date: m.date)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    (Text(m.weight.map { (m.weightEstimated ? "≈" : "") + Fmt.weight($0) } ?? "–").font(.title3)
                     + Text(" kg").font(.subheadline))
                        .foregroundColor(Theme.weightLine)
                    if let c = m.change, abs(c) >= 0.05 {
                        Text(String(format: "%@%.1f", c > 0 ? "▲" : "▼", abs(c)))
                            .font(.caption)
                            .foregroundStyle(c > 0 ? Theme.high : Theme.normal)
                    }
                }
                HStack(spacing: 10) {
                    value("BMI", m.bmi, "")
                    value("Fat", m.bodyFat, "%")
                }
                value("Lean", m.leanMass, " kg")
                if let x = m.extra, x.hasExtras {
                    ExtraLine(x: x)
                }
            }
            .foregroundStyle(Theme.primaryText)

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                Text(Fmt.time(m.date))
                if let bmi = m.bmi {
                    let c = BodyStore.bmiCategory(bmi)
                    Text(c.0).font(.caption2).foregroundStyle(c.1)
                }
                Text(m.source)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.primaryText)
        }
    }

    @ViewBuilder
    private func value(_ label: String, _ v: Double?, _ unit: String) -> some View {
        if let v {
            (Text("\(label) ").foregroundColor(Theme.secondaryText)
             + Text(String(format: "%.1f", v) + unit))
                .font(.subheadline)
        }
    }
}

/// Shown when Weight can't be read but other body data arrives: weights are estimated
/// until read access to Weight is allowed.
struct WeightAccessHint: View {
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Weight is not shared with BP Companion", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.elevated)
            Text("Weights marked ≈ are estimated from lean mass and body fat (lean ÷ (1 − fat%)). Tap below to allow reading Weight.")
                .font(.footnote)
                .foregroundStyle(Theme.primaryText)
            Button {
                asking = true
                Task {
                    try? await HealthSync.shared.requestWeightRead()
                    await BodyStore.shared.refresh()
                    asking = false
                }
            } label: {
                HStack {
                    Label("Allow Weight Access", systemImage: "heart.text.square")
                    if asking { ProgressView().padding(.leading, 4) }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.orange, in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(asking)
            Text("If no permission sheet appears: iPhone — Health app › Sharing › Apps › BP Companion › Weight; iPad — Settings › Health › Data Access & Devices › BP Companion › Weight.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.cell, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.elevated.opacity(0.6), lineWidth: 1))
    }
}

/// Empty Body / Weight screen that says *why* nothing is shown:
/// data found but every app is turned off in Body Data Sources, or nothing readable
/// (read access off on this device, or Health on this device has no data yet).
struct BodyEmptyState: View {
    @ObservedObject private var bodyStore = BodyStore.shared
    @State private var asking = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "scalemass")
                .font(.system(size: 44))
                .foregroundStyle(Theme.secondaryText)
            if !bodyStore.allSources.isEmpty {
                Text("All Body Data Is Turned Off").font(.title3.bold())
                Text("Found in Health from: \(bodyStore.allSources.joined(separator: ", ")). These apps are turned off in Body Data Sources.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.secondaryText)
                ForEach(bodyStore.allSources, id: \.self) { name in
                    Button("Turn On \(name)") { bodyStore.setIncluded(name, true) }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.orange)
                }
            } else if !bodyStore.isAvailable || !UserDefaults.standard.bool(forKey: SettingsKey.healthReadBody) {
                Text("No Body Data on This Device").font(.title3.bold())
                Text(bodyStore.isAvailable
                     ? "Read Body Data is off (Settings › Apple Health). You can also import your YUNMAI history in Settings › Data › Import YUNMAI Data — it syncs to your other devices through iCloud."
                     : "Apple Health is not on this device. Import your YUNMAI history in Settings › Data › Import YUNMAI Data (on any device) — it syncs here through iCloud.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("No Body Data Readable").font(.title3.bold())
                Text("BP Companion can't read weight, BMI or body fat on this device. Read access is set separately on each device, and iPad gets YUNMAI data from iPhone through iCloud (Settings › [your name] › iCloud › Health on both).")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.secondaryText)
                Button {
                    asking = true
                    Task {
                        try? await HealthSync.shared.requestAuthorization()
                        try? await HealthSync.shared.requestWeightRead()
                        await bodyStore.refresh()
                        asking = false
                    }
                } label: {
                    HStack {
                        Text("Allow Health Access")
                        if asking { ProgressView() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.orange)
                .disabled(asking)
                Text("If no sheet appears — iPhone: Health app › Sharing › Apps › BP Companion. iPad: Settings › Health › Data Access & Devices › BP Companion. Turn on Weight, BMI, Body Fat, Lean Body Mass and Height.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.secondaryText)
            }
            Button("Reload") { Task { await bodyStore.refresh() } }
                .foregroundStyle(Theme.label)
        }
        .padding(24)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Items YUNMAI records but does not send to Health (from the imported history).
struct ExtraLine: View {
    let x: BodyStore.Imported

    var body: some View {
        let parts: [String] = [
            x.skeletalMuscle.map { String(format: "Skeletal %.1f%%", $0) },
            x.water.map { String(format: "Water %.1f%%", $0) },
            x.protein.map { String(format: "Protein %.1f%%", $0) },
            x.visceralFat.map { String(format: "Visceral %.0f", $0) },
            x.bonePercent.map { String(format: "Bone %.1f%%", $0) },
            x.bmr.map { String(format: "BMR %.0f", $0) },
            x.bodyAge.map { String(format: "Age %.0f", $0) },
            x.fatMass.map { String(format: "Fat mass %.1f kg", $0) },
        ].compactMap { $0 }
        return Text(parts.joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
