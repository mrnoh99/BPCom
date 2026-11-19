import SwiftUI

/// Page 4: Max / Avg / Min bars for systolic, diastolic and heart rate.
struct StatisticsPage: View {
    let readings: [Reading]

    private let maxColor = Color(red: 1.00, green: 0.36, blue: 0.20)
    private let avgColor = Color(red: 1.00, green: 0.72, blue: 0.10)
    private let minColor = Color(red: 0.25, green: 0.80, blue: 0.25)

    private struct BarGroup: Identifiable {
        let id: String
        let unit: String
        let agg: Aggregate?
        let level: (Double) -> BPLevel?
    }

    private var groups: [BarGroup] {
        let s = ReadingStats(readings)
        return [
            BarGroup(id: "Systolic", unit: "(mmHg)", agg: s.systolic, level: { BPLevel.systolic($0) }),
            BarGroup(id: "Diastolic", unit: "(mmHg)", agg: s.diastolic, level: { BPLevel.diastolic($0) }),
            BarGroup(id: "Heart Rate", unit: "(bpm)", agg: s.pulse, level: { _ in nil }),
        ]
    }

    var body: some View {
        let gs = groups
        let top = max(200, (gs.compactMap { $0.agg?.max }.max() ?? 0) * 1.1)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(gs) { g in
                    HStack(spacing: 4) {
                        Text(g.id).foregroundStyle(Theme.label)
                        Text(g.unit).foregroundStyle(.white.opacity(0.85))
                    }
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)

            GeometryReader { geo in
                let h = geo.size.height - 22   // room for x labels
                ZStack(alignment: .topLeading) {
                    bands(height: h, top: top)
                    HStack(spacing: 0) {
                        ForEach(gs) { g in
                            groupBars(g, height: h, top: top)
                                .frame(maxWidth: .infinity)
                            if g.id != gs.last?.id {
                                Rectangle().fill(Color.black.opacity(0.15)).frame(width: 1, height: h)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
        }
        .background(Theme.background)
        .overlay {
            if readings.isEmpty {
                Text("No readings in this period.")
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    /// Red (high) / green (normal) / yellow (low) background zones.
    private func bands(height h: CGFloat, top: Double) -> some View {
        func y(_ v: Double) -> CGFloat { h * CGFloat(1 - v / top) }
        return VStack(spacing: 0) {
            Color(red: 1.0, green: 0.86, blue: 0.84).frame(height: y(140))
            Color(red: 0.88, green: 0.97, blue: 0.86).frame(height: y(60) - y(140))
            Color(red: 1.0, green: 0.97, blue: 0.86).frame(height: h - y(60))
        }
    }

    private func groupBars(_ g: BarGroup, height h: CGFloat, top: Double) -> some View {
        let values: [(String, Double?, Color)] = [
            ("Max", g.agg?.max, maxColor),
            ("Avg", g.agg?.avg, avgColor),
            ("Min", g.agg?.min, minColor),
        ]
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(values.indices, id: \.self) { i in
                let value = values[i].1
                VStack(spacing: 2) {
                    Spacer(minLength: 0)
                    if let v = value {
                        Text(Fmt.int(v))
                            .font(.caption2.bold())
                            .foregroundStyle(g.level(v).map { $0 == .normal ? Color(red: 0.1, green: 0.55, blue: 0.1) : Theme.color(for: $0) } ?? .black)
                        Rectangle()
                            .fill(values[i].2)
                            .frame(width: 16, height: max(0, h * CGFloat(v / top)))
                    }
                    Text(values[i].0)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(height: 22)
                }
                .frame(height: h + 22)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
