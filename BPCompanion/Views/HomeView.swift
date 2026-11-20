import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Reading.date, order: .reverse) private var readings: [Reading]
    @AppStorage(SettingsKey.ownerName) private var ownerName = SettingsKey.defaultOwnerName
    @State private var showAdd = false
    @ObservedObject private var bodyStore = BodyStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    SectionTitle("LAST 10 READINGS")
                    StatsTable(stats: ReadingStats(Array(readings.prefix(10))))

                    Theme.separator.frame(height: 18)

                    SectionTitle("YOUR LAST READINGS")
                    lastReading

                    if let m = lastWeighIn {
                        Theme.separator.frame(height: 18)
                        SectionTitle("YOUR LAST WEIGH-IN")
                        weighIn(m)
                    }

                    Text(AppInfo.credit)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .readableWidth()
            }
            .background(Theme.background)
            .task { await bodyStore.refresh() }
            .refreshable { await bodyStore.refresh() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { title }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle").font(.title2)
                    }
                    .accessibilityLabel("Add Entry")
                }
            }
            .orangeNavigationBar()
            .sheet(isPresented: $showAdd) {
                AddEntryView(editing: nil, template: readings.first)
            }
        }
    }

    /// "BP C♥mpanion of Jaisung NOH"
    private var title: some View {
        (Text("BP C")
         + Text(Image(systemName: "heart.fill")).foregroundColor(.red)
         + Text("mpanion of \(ownerName)"))
            .font(.headline)
            .foregroundColor(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    @ViewBuilder
    private var lastReading: some View {
        if let r = readings.first {
            VStack(spacing: 1) {
                lastRow("SYSTOLIC/DIASTOLIC:", "\(r.systolic)/\(r.diastolic) mmHg")
                lastRow("HEART RATE:", "\(r.pulse) bpm")
                lastRow("MAP:", "\(Fmt.int(r.map)) mmHg")
                lastRow("DATE:", Fmt.dateTime(r.date))
            }
            .background(Theme.gridLine)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "heart.text.square").font(.system(size: 44))
                    .foregroundStyle(Theme.orange)
                Text("No readings yet.\nTap + to add your first blood pressure.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }

    /// Newest weigh-in from Apple Health (e.g. the YUNMAI scale) and the imported history.
    private var lastWeighIn: WeightHistoryList.Measurement? {
        WeightHistoryList.measurements(from: bodyStore.samples, extra: bodyStore.extra(at:)).first
    }

    private func weighIn(_ m: WeightHistoryList.Measurement) -> some View {
        VStack(spacing: 1) {
            if let w = m.weight {
                let change = m.change.map { abs($0) >= 0.05 ? String(format: "  (%@%.1f)", $0 > 0 ? "▲" : "▼", abs($0)) : "" } ?? ""
                lastRow("WEIGHT:", (m.weightEstimated ? "≈" : "") + "\(Fmt.weight(w)) kg" + change)
            }
            if let bmi = m.bmi {
                lastRow("BMI:", String(format: "%.1f · ", bmi) + BodyStore.bmiCategory(bmi).0)
            }
            if let f = m.bodyFat { lastRow("BODY FAT:", String(format: "%.1f %%", f)) }
            if let l = m.leanMass { lastRow("LEAN MASS:", String(format: "%.1f kg", l)) }
            if let s = m.extra?.skeletalMuscle { lastRow("SKELETAL MUSCLE:", String(format: "%.1f %%", s)) }
            if let v = m.extra?.visceralFat { lastRow("VISCERAL FAT:", String(format: "%.0f", v)) }
            lastRow("DATE:", "\(Fmt.dateTime(m.date)) · \(m.source)")
        }
        .background(Theme.gridLine)
    }

    private func lastRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(Theme.label)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(value)
                .foregroundStyle(Theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.body)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(Theme.cell)
    }
}
