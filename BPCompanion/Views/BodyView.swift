import SwiftUI
import Charts

/// Body tab: weight, BMI, body fat and lean body mass from Apple Health (YUNMAI etc.),
/// analysed on its own — latest values, period summary, trend chart and change analysis.
struct BodyView: View {
    @StateObject private var body_ = BodyStore.shared
    @AppStorage(SettingsKey.healthReadBody) private var readBody = true

    @State private var period = ReportPeriod(kind: .month)
    @State private var showCustom = false
    @State private var metric: BodyStore.Metric = .weight
    @State private var source: String?        // nil = all apps

    typealias Metric = BodyStore.Metric

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !body_.isAvailable {
                    unavailable("Health Not Available",
                                "Apple Health is not available on this device. Open BP Companion on iPhone to see body data from your scale.")
                } else if !readBody {
                    unavailable("Body Data Is Off",
                                "Turn on Settings › Apple Health › Read Body Data to see weight, BMI, body fat and lean mass from your scale app.")
                } else if body_.loaded && body_.samples.values.allSatisfy({ $0.isEmpty }) && body_.heights.isEmpty {
                    unavailable("No Body Data",
                                "No weight or body composition found in Health. In the YUNMAI app, turn on Health sharing (Me › Connect to Health), then allow BP Companion to read it in Health › Sharing › Apps.")
                } else {
                    PeriodHeader(period: $period)
                    Theme.separator.frame(height: 4)
                    ScrollView {
                        VStack(spacing: 0) {
                            latestCard
                            Theme.separator.frame(height: 4)
                            summaryTable
                            Theme.separator.frame(height: 4)
                            trend
                            Theme.separator.frame(height: 4)
                            analysis
                        }
                        .readableWidth()
                    }
                    Theme.separator.frame(height: 4)
                    PeriodSelector(period: $period, filter: .constant(.all), showCustom: $showCustom, showsFilter: false)
                }
            }
            .background(Theme.background)
            .navigationTitle("Body")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if body_.sources.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) { sourceMenu }
                }
            }
            .orangeNavigationBar()
            .sheet(isPresented: $showCustom) {
                CustomRangeSheet(period: $period).presentationDetents([.medium])
            }
            .task { await body_.refresh() }
            .refreshable { await body_.refresh() }
        }
    }

    // MARK: Data for the period

    private func inPeriod(_ m: Metric) -> [BodyStore.Sample] {
        (body_.samples[m] ?? []).filter {
            period.contains($0.date) && (source == nil || $0.source == source)
        }
    }

    private struct DayPoint: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    /// One point per day (the day's average) for the chart.
    private func daily(_ m: Metric) -> [DayPoint] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: inPeriod(m)) { cal.startOfDay(for: $0.date) }
        return groups.keys.sorted().map { d in
            let v = groups[d]!.map(\.value)
            return DayPoint(date: d, value: v.reduce(0, +) / Double(v.count))
        }
    }

    // MARK: Sections

    private var latestCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LATEST")
                    .font(.title3)
                    .foregroundStyle(Theme.label)
                Spacer()
                if let w = body_.latest(.weight, source: source) {
                    Text("\(Fmt.dateTime(w.date)) · \(w.source)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Metric.allCases) { m in
                    tile(m)
                }
            }
            heightTile
        }
        .padding(12)
    }

    private func tile(_ m: Metric) -> some View {
        let s = body_.latest(m, source: source)
        return VStack(alignment: .leading, spacing: 4) {
            Text(m.title).font(.caption).foregroundStyle(Theme.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(s.map { m.format($0.value) } ?? "–")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(m.color)
                    .monospacedDigit()
                Text(m.unit).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            if m == .bmi, let v = s?.value {
                let c = BodyStore.bmiCategory(v)
                Text(c.0).font(.caption2).foregroundStyle(c.1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.cell, in: RoundedRectangle(cornerRadius: 10))
    }

    /// Height from the scale app (latest value; it rarely changes).
    private var heightTile: some View {
        let h = body_.latestHeight(source: source)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Height").font(.caption).foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(h.map { String(format: "%.1f", $0.value) } ?? "–")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .monospacedDigit()
            Text("cm").font(.caption).foregroundStyle(Theme.secondaryText)
            if let h {
                Text(h.date.formatted(.dateTime.year().month().day()))
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(10)
        .background(Theme.cell, in: RoundedRectangle(cornerRadius: 10))
    }

    private var summaryTable: some View {
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            GridRow {
                Theme.cellHeader.frame(height: 36)
                ForEach(["MAX", "MIN", "AVG", "CHANGE"], id: \.self) { h in
                    Text(h).font(.subheadline).foregroundStyle(Theme.label)
                        .frame(maxWidth: .infinity, minHeight: 36).background(Theme.cellHeader)
                }
            }
            ForEach(Metric.allCases) { m in
                let v = inPeriod(m)
                let agg = Aggregate(v.map(\.value))
                let change = v.count >= 2 ? v.last!.value - v.first!.value : nil
                GridRow {
                    Text(m.title.uppercased())
                        .font(.caption)
                        .foregroundStyle(Theme.label)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 46).background(Theme.cellHeader)
                    cell(agg.map { m.format($0.max) }, m.unit)
                    cell(agg.map { m.format($0.min) }, m.unit)
                    cell(agg.map { m.format($0.avg) }, m.unit)
                    cell(change.map { ($0 > 0 ? "+" : "") + m.format($0) }, m == .bodyFat ? "%p" : m.unit)
                }
            }
        }
        .background(Theme.gridLine)
    }

    private func cell(_ value: String?, _ unit: String) -> some View {
        VStack(spacing: 0) {
            Text(value ?? "–").foregroundStyle(Theme.primaryText).monospacedDigit()
            if !unit.isEmpty {
                Text(unit).font(.caption2).foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(Theme.cell)
    }

    private var trend: some View {
        VStack(spacing: 8) {
            Picker("Metric", selection: $metric) {
                ForEach(Metric.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 10)

            let points = daily(metric)
            if points.isEmpty {
                Text("No \(metric.title.lowercased()) in this period.")
                    .foregroundStyle(Theme.secondaryText)
                    .frame(height: 220)
            } else {
                let values = points.map(\.value)
                let avg = values.reduce(0, +) / Double(values.count)
                let pad = max(0.5, (values.max()! - values.min()!) * 0.2)
                Chart {
                    ForEach(points) { p in
                        LineMark(x: .value("Date", p.date), y: .value(metric.title, p.value))
                            .foregroundStyle(metric.color)
                        PointMark(x: .value("Date", p.date), y: .value(metric.title, p.value))
                            .foregroundStyle(metric.color)
                            .symbolSize(points.count > 60 ? 10 : 30)
                    }
                    RuleMark(y: .value("Average", avg))
                        .foregroundStyle(metric.color.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("avg \(metric.format(avg))\(metric.unit)")
                                .font(.caption2).foregroundStyle(metric.color)
                        }
                }
                .chartXScale(domain: period.from...period.end)
                .chartYScale(domain: (values.min()! - pad)...(values.max()! + pad))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [4, 4]))
                            .foregroundStyle(Color.white.opacity(0.3))
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [4, 4]))
                            .foregroundStyle(Color.white.opacity(0.3))
                        AxisValueLabel().foregroundStyle(Color.white.opacity(0.85))
                    }
                }
                .frame(height: 240)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
    }

    /// Plain-language reading of how weight, body fat and lean mass moved in the period.
    private var analysis: some View {
        let w = inPeriod(.weight), f = inPeriod(.bodyFat), l = inPeriod(.leanMass)
        func delta(_ s: [BodyStore.Sample]) -> Double? { s.count >= 2 ? s.last!.value - s.first!.value : nil }
        let dW = delta(w), dF = delta(f), dL = delta(l)

        var lines: [String] = []
        if let dW, let first = w.first {
            let pct = dW / first.value * 100
            lines.append(String(format: "Weight %@%.1f kg (%@%.1f%%) over %d measurements.",
                                dW >= 0 ? "+" : "", dW, pct >= 0 ? "+" : "", pct, w.count))
        }
        if let dF { lines.append(String(format: "Body fat %@%.1f %%p.", dF >= 0 ? "+" : "", dF)) }
        if let dL { lines.append(String(format: "Lean mass %@%.1f kg.", dL >= 0 ? "+" : "", dL)) }

        var verdict: (String, Color)?
        if let dW {
            switch (dW, dL ?? 0, dF ?? 0) {
            case let (w, l, _) where w <= -0.5 && l >= -0.2:
                verdict = ("Losing fat while keeping lean mass — good direction.", Theme.normal)
            case let (w, l, _) where w <= -0.5 && l < -0.2:
                verdict = ("Losing weight, but some of it is lean mass — consider protein and strength exercise.", Theme.elevated)
            case let (w, _, f) where w >= 0.5 && f > 0.3:
                verdict = ("Weight going up, mostly as body fat.", Theme.high)
            case let (w, l, f) where w >= 0.5 && l > 0.3 && f <= 0:
                verdict = ("Weight going up as lean mass.", Theme.normal)
            default:
                verdict = ("Weight is stable in this period.", Theme.secondaryText)
            }
        }

        return VStack(alignment: .leading, spacing: 8) {
            Text("ANALYSIS")
                .font(.title3)
                .foregroundStyle(Theme.label)
            if lines.isEmpty {
                Text("At least two measurements in the period are needed.")
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(lines, id: \.self) { Text($0).foregroundStyle(Theme.primaryText) }
                if let verdict {
                    Text(verdict.0).font(.headline).foregroundStyle(verdict.1)
                }
            }
            if let bmi = body_.latest(.bmi, source: source)?.value {
                let c = BodyStore.bmiCategory(bmi)
                Text("Latest BMI \(BodyStore.Metric.bmi.format(bmi)) — \(c.0) (Asian criteria: normal 18.5–22.9).")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    // MARK: Pieces

    private var sourceMenu: some View {
        Menu {
            Picker("Source", selection: $source) {
                Text("All apps").tag(String?.none)
                ForEach(body_.sources, id: \.self) { Text($0).tag(String?.some($0)) }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle").font(.title3)
        }
    }

    private func unavailable(_ title: String, _ message: String) -> some View {
        ContentUnavailableView(title, systemImage: "scalemass", description: Text(message))
            .frame(maxHeight: .infinity)
    }
}
