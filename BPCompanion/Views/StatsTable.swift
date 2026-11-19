import SwiftUI

/// MAX / MIN / AVG table used on Home ("LAST 10 READINGS") and Reports › Summary.
struct StatsTable: View {
    let stats: ReadingStats
    var rowHeight: CGFloat = 46

    var body: some View {
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            GridRow {
                Theme.cellHeader.frame(height: rowHeight * 0.85)
                header("MAX")
                header("MIN")
                header("AVG")
            }
            row("SYSTOLIC", stats.systolic, unit: "mmHg", format: Fmt.int)
            row("DIASTOLIC", stats.diastolic, unit: "mmHg", format: Fmt.int)
            row("HR", stats.pulse, unit: "bpm", format: Fmt.int)
            row("MAP", stats.map, unit: "mmHg", format: Fmt.int)
        }
        .background(Theme.gridLine)
    }

    private func header(_ s: String) -> some View {
        Text(s)
            .font(.subheadline)
            .foregroundStyle(Theme.label)
            .frame(maxWidth: .infinity, minHeight: rowHeight * 0.85)
            .background(Theme.cellHeader)
    }

    @ViewBuilder
    private func row(_ title: String, _ agg: Aggregate?, unit: String, format: (Double) -> String) -> some View {
        GridRow {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: rowHeight)
                .background(Theme.cellHeader)
            cell(agg.map { format($0.max) }, unit)
            cell(agg.map { format($0.min) }, unit)
            cell(agg.map { format($0.avg) }, unit)
        }
    }

    private func cell(_ value: String?, _ unit: String) -> some View {
        VStack(spacing: 0) {
            Text(value ?? "–")
                .font(.body)
                .foregroundStyle(Theme.primaryText)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: rowHeight)
        .background(Theme.cell)
    }
}

/// Orange upper-case section title ("LAST 10 READINGS").
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.title3)
            .foregroundStyle(Theme.label)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 14)
            .background(Theme.background)
    }
}
