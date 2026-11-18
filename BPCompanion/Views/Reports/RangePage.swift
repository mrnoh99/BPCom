import SwiftUI

/// Page 3: how many readings fall in each systolic / diastolic band.
struct RangePage: View {
    let readings: [Reading]

    private struct Band {
        let title: String
        let level: BPLevel
    }

    private let sysBands = [Band(title: "< 90", level: .low), Band(title: "90~119", level: .normal),
                            Band(title: "120~139", level: .elevated), Band(title: "> 139", level: .high)]
    private let diaBands = [Band(title: "< 60", level: .low), Band(title: "60~79", level: .normal),
                            Band(title: "80~89", level: .elevated), Band(title: "> 89", level: .high)]

    // Row tints
    private let headerTint = Color(red: 1.00, green: 0.86, blue: 0.84)
    private let countTint = Color(red: 0.86, green: 0.96, blue: 0.86)
    private let percentTint = Color(red: 1.00, green: 0.96, blue: 0.84)

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                block("Systolic", bands: sysBands, levels: readings.map(\.systolicLevel))
                Theme.separator.frame(height: 4)
                block("Diastolic", bands: diaBands, levels: readings.map(\.diastolicLevel))
            }
        }
        .background(Theme.background)
    }

    private func block(_ title: String, bands: [Band], levels: [BPLevel]) -> some View {
        let total = levels.count
        let counts = bands.map { b in levels.filter { $0 == b.level }.count }
        // "Normal" = everything that is neither low nor high (normal + elevated, i.e. ≤ 139 / ≤ 89)
        let normal = levels.filter { $0 == .normal || $0 == .elevated }.count
        func pct(_ n: Int) -> String { Fmt.percent(total == 0 ? 0 : Double(n) * 100 / Double(total)) }

        return VStack(spacing: 0) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)

            Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                GridRow {
                    ForEach(bands.indices, id: \.self) { i in cell(bands[i].title, .black, headerTint) }
                    cell("Normal", .black, headerTint)
                }
                GridRow {
                    ForEach(bands.indices, id: \.self) { i in
                        cell("\(counts[i])", Theme.color(for: bands[i].level), countTint)
                    }
                    cell("\(normal)", .black, countTint)
                }
                GridRow {
                    ForEach(bands.indices, id: \.self) { i in
                        cell(pct(counts[i]), Theme.color(for: bands[i].level), percentTint)
                    }
                    cell(pct(normal), .black, percentTint)
                }
            }
            .background(Theme.gridLine)
        }
    }

    private func cell(_ text: String, _ fg: Color, _ bg: Color) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(fg == Theme.normal ? Color(red: 0.1, green: 0.6, blue: 0.1) : fg)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(bg)
    }
}
