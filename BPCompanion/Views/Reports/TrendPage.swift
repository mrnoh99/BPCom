import SwiftUI
import Charts

/// Page 2: line chart of BP / HR with dashed average lines.
/// (Body weight is analysed separately in Reports › Weight, from Apple Health.)
struct TrendPage: View {
    let readings: [Reading]
    let period: ReportPeriod

    enum Metric: String, CaseIterable { case bp = "BP", hr = "HR" }
    @State private var metric: Metric = .bp

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let sys: Double
        let dia: Double
        let pulse: Double
    }

    private enum Bucket { case reading, day, month }

    private var bucket: Bucket {
        switch period.kind {
        case .day: return .reading
        case .year: return .month
        case .custom: return period.dayCount > 92 ? .month : .day
        default: return .day
        }
    }

    private var cal: Calendar { .current }

    /// Readings averaged per bucket (individual readings for D).
    private var points: [Point] {
        func avg(_ v: [Double]) -> Double { v.reduce(0, +) / Double(max(v.count, 1)) }
        func make(_ date: Date, _ rs: [Reading]) -> Point {
            return Point(date: date,
                         sys: avg(rs.map { Double($0.systolic) }),
                         dia: avg(rs.map { Double($0.diastolic) }),
                         pulse: avg(rs.map { Double($0.pulse) }))
        }
        switch bucket {
        case .reading:
            return readings.map { make($0.date, [$0]) }
        case .day, .month:
            let key: (Date) -> Date = bucket == .day
                ? { cal.startOfDay(for: $0) }
                : { cal.date(from: cal.dateComponents([.year, .month], from: $0))! }
            let groups = Dictionary(grouping: readings, by: { key($0.date) })
            return groups.keys.sorted().map { make($0, groups[$0]!) }
        }
    }

    private var xDomain: ClosedRange<Date> {
        switch bucket {
        case .reading:
            return period.from...period.end
        case .day:
            return period.from.addingTimeInterval(-12 * 3600)...period.end.addingTimeInterval(-12 * 3600)
        case .month:
            let first = cal.date(from: cal.dateComponents([.year, .month], from: period.from))!
            let last = cal.date(from: cal.dateComponents([.year, .month], from: period.to))!
            return first.addingTimeInterval(-15 * 86400)...last.addingTimeInterval(15 * 86400)
        }
    }

    private var xValues: [Date] {
        var out: [Date] = []
        switch bucket {
        case .reading:
            var d = period.from
            while d <= period.end { out.append(d); d = cal.date(byAdding: .hour, value: 4, to: d)! }
        case .day:
            let n = period.dayCount
            let step = n <= 7 ? 1 : (n <= 14 ? 2 : Int((Double(n) / 6).rounded(.up)))
            var d = period.from
            while d < period.end { out.append(d); d = cal.date(byAdding: .day, value: step, to: d)! }
        case .month:
            var d = cal.date(from: cal.dateComponents([.year, .month], from: period.from))!
            let n = (cal.dateComponents([.month], from: d, to: period.to).month ?? 12) + 1
            let step = n <= 12 ? 1 : Int((Double(n) / 12).rounded(.up))
            while d <= period.to { out.append(d); d = cal.date(byAdding: .month, value: step, to: d)! }
        }
        return out
    }

    private var xFormat: Date.FormatStyle {
        switch bucket {
        case .reading: return .dateTime.hour()
        case .day: return period.dayCount <= 7 ? .dateTime.weekday(.abbreviated) : .dateTime.month(.defaultDigits).day()
        case .month: return .dateTime.month(.narrow)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            metricTabs
            legend
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            if points.isEmpty {
                ContentUnavailableView("No Data", systemImage: "chart.xyaxis.line",
                                       description: Text("No readings in this period."))
                    .frame(maxHeight: .infinity)
            } else {
                chart
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        }
        .background(Theme.background)
    }

    private var metricTabs: some View {
        HStack(spacing: 0) {
            ForEach(Metric.allCases, id: \.self) { m in
                Button { metric = m } label: {
                    VStack(spacing: 10) {
                        Text(m.rawValue)
                            .font(.title3)
                            .foregroundStyle(metric == m ? Theme.label : Color.white.opacity(0.85))
                            .padding(.top, 10)
                        Rectangle()
                            .fill(metric == m ? Theme.orange : Color.black)
                            .frame(height: 3)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var legend: some View {
        HStack(alignment: .top) {
            Text(metric == .bp ? "mmHg" : "bpm")
                .foregroundStyle(Theme.label)
            Spacer()
            switch metric {
            case .bp:
                VStack(alignment: .leading, spacing: 6) {
                    legendItem("Systolic", Theme.systolicLine, dashed: false)
                    legendItem("Diastolic", Theme.diastolicLine, dashed: false)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    legendItem("Avg Systolic", Theme.systolicLine, dashed: true)
                    legendItem("Avg Diastolic", Theme.diastolicLine, dashed: true)
                }
            case .hr:
                legendItem("Heart Rate", Theme.pulseLine, dashed: false)
                Spacer()
                legendItem("Avg Heart Rate", Theme.pulseLine, dashed: true)
            }
        }
        .font(.subheadline)
    }

    private func legendItem(_ title: String, _ color: Color, dashed: Bool) -> some View {
        HStack(spacing: 4) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 1))
                p.addLine(to: CGPoint(x: 20, y: 1))
            }
            .stroke(color, style: StrokeStyle(lineWidth: dashed ? 1.5 : 3, dash: dashed ? [4, 3] : []))
            .frame(width: 20, height: 2)
            Text(title).foregroundStyle(.white.opacity(0.9))
        }
    }

    // MARK: Chart

    @ViewBuilder
    private var chart: some View {
        switch metric {
        case .bp:
            let s = points.map(\.sys), d = points.map(\.dia)
            Chart {
                ForEach(points) { p in
                    LineMark(x: .value("Date", p.date), y: .value("mmHg", p.sys), series: .value("Series", "Systolic"))
                        .foregroundStyle(Theme.systolicLine)
                    PointMark(x: .value("Date", p.date), y: .value("mmHg", p.sys))
                        .foregroundStyle(Theme.color(for: BPLevel.systolic(p.sys)))
                    LineMark(x: .value("Date", p.date), y: .value("mmHg", p.dia), series: .value("Series", "Diastolic"))
                        .foregroundStyle(Theme.diastolicLine)
                    PointMark(x: .value("Date", p.date), y: .value("mmHg", p.dia))
                        .foregroundStyle(Theme.color(for: BPLevel.diastolic(p.dia)))
                }
                RuleMark(y: .value("Avg Systolic", mean(s)))
                    .foregroundStyle(Theme.systolicLine)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
                RuleMark(y: .value("Avg Diastolic", mean(d)))
                    .foregroundStyle(Theme.diastolicLine)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
            }
            .modifier(AxisStyle(xDomain: xDomain, yDomain: yDomain(s + d), xValues: xValues, xFormat: xFormat))

        case .hr:
            let v = points.map(\.pulse)
            Chart {
                ForEach(points) { p in
                    LineMark(x: .value("Date", p.date), y: .value("bpm", p.pulse))
                        .foregroundStyle(Theme.pulseLine)
                    PointMark(x: .value("Date", p.date), y: .value("bpm", p.pulse))
                        .foregroundStyle(Theme.pulseLine)
                }
                RuleMark(y: .value("Avg", mean(v)))
                    .foregroundStyle(Theme.pulseLine)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
            }
            .modifier(AxisStyle(xDomain: xDomain, yDomain: yDomain(v), xValues: xValues, xFormat: xFormat))

        }
    }

    private func mean(_ v: [Double]) -> Double { v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count) }

    private func yDomain(_ v: [Double], pad: Double = 10) -> ClosedRange<Double> {
        let lo = (v.min() ?? 60) - pad
        let hi = (v.max() ?? 160) + pad
        return lo.rounded(.down)...hi.rounded(.up)
    }
}

/// Dashed grid + axis labels shared by the three charts.
private struct AxisStyle: ViewModifier {
    let xDomain: ClosedRange<Date>
    let yDomain: ClosedRange<Double>
    let xValues: [Date]
    let xFormat: Date.FormatStyle

    func body(content: Content) -> some View {
        content
            .chartXScale(domain: xDomain)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: xValues) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [4, 4]))
                        .foregroundStyle(Color.white.opacity(0.35))
                    AxisValueLabel(format: xFormat)
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [4, 4]))
                        .foregroundStyle(Color.white.opacity(0.35))
                    AxisValueLabel()
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            }
    }
}
