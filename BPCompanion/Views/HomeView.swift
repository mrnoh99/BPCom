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

                    Text("Developed by Jaisung NOH MD 2026")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .readableWidth()
            }
            .background(Theme.background)
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
                if let w = bodyStore.latest(.weight) {
                    // From Apple Health (e.g. the YUNMAI scale), independent of BP readings.
                    lastRow("WEIGHT:", "\(Fmt.weight(w.value)) kg · \(w.date.formatted(.dateTime.month().day()))")
                }
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
