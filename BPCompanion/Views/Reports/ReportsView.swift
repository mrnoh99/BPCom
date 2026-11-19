import SwiftUI
import SwiftData
import UIKit

/// Reports: four pages selected by swiping – Summary, Trend chart, Range, Statistics.
struct ReportsView: View {
    @Query(sort: \Reading.date) private var allReadings: [Reading]

    @State private var period = ReportPeriod()
    @State private var filter: TimeFilter = .all
    @State private var page = 0
    @State private var showCustom = false
    @State private var shareItem: ShareImage?

    private let titles = ["Summary", "Trend", "Range", "Statistics"]

    private var readings: [Reading] {
        allReadings.filter { period.contains($0.date) && filter.includes($0.date) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PeriodHeader(period: $period)
                Theme.separator.frame(height: 4)

                TabView(selection: $page) {
                    ForEach(0..<4, id: \.self) { i in
                        pageView(i).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .never))

                Theme.separator.frame(height: 4)
                PeriodSelector(period: $period, filter: $filter, showCustom: $showCustom)
            }
            .background(Theme.background)
            .navigationTitle(titles[page])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: snapshot) {
                        Image(systemName: "camera").font(.title3)
                    }
                    .accessibilityLabel("Share snapshot")
                }
            }
            .orangeNavigationBar()
            .sheet(isPresented: $showCustom) {
                CustomRangeSheet(period: $period)
                    .presentationDetents([.medium])
            }
            .sheet(item: $shareItem) { item in
                ActivityView(items: [item.image])
            }
        }
    }

    @ViewBuilder
    private func pageView(_ i: Int) -> some View {
        switch i {
        case 0:
            VStack(spacing: 0) {
                StatsTable(stats: ReadingStats(readings), rowHeight: 58)
                Spacer(minLength: 0)
            }
            .readableWidth()
            .padding(.bottom, 28)
        case 1: TrendPage(readings: readings, period: period).padding(.bottom, 28)
        case 2: RangePage(readings: readings).readableWidth().padding(.bottom, 28)
        default: StatisticsPage(readings: readings).padding(.bottom, 28)
        }
    }

    /// Camera button: renders the current page (with its period) to an image and opens the share sheet.
    @MainActor
    private func snapshot() {
        let content = VStack(spacing: 0) {
            Text("\(titles[page]) · \(filter.rawValue)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.header)
            PeriodHeader(period: .constant(period), showsArrows: false)
            pageView(page).frame(height: 620)
        }
        .frame(width: 400)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        if let image = renderer.uiImage {
            shareItem = ShareImage(image: image)
        }
    }
}

struct ShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - From / To header

struct PeriodHeader: View {
    @Binding var period: ReportPeriod
    var showsArrows = true

    var body: some View {
        HStack {
            arrow("chevron.left", enabled: true) { period.shift(-1) }
            Spacer()
            column("From", period.from)
            Spacer()
            column("To", period.to)
            Spacer()
            arrow("chevron.right", enabled: period.canGoForward) { period.shift(1) }
        }
        .padding(.vertical, 8)
        .background(Theme.background)
    }

    private func column(_ title: String, _ date: Date) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.title3).foregroundStyle(.white)
            Text(Fmt.date(date)).font(.subheadline).foregroundStyle(Theme.label)
        }
    }

    @ViewBuilder
    private func arrow(_ name: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        if showsArrows {
            Button(action: { withAnimation { action() } }) {
                Image(systemName: name)
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(enabled ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
            .disabled(!enabled)
        } else {
            Color.clear.frame(width: 44, height: 44)
        }
    }
}

// MARK: - D W M Y Custom + All/AM/PM

struct PeriodSelector: View {
    @Binding var period: ReportPeriod
    @Binding var filter: TimeFilter
    @Binding var showCustom: Bool

    var body: some View {
        HStack {
            HStack(spacing: 0) {
                ForEach(PeriodKind.allCases) { k in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { period.kind = k }
                        if k == .custom { showCustom = true }
                    } label: {
                        Text(k.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(period.kind == k ? Color.white : Theme.label)
                            .padding(.horizontal, k == .custom ? 14 : 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(period.kind == k ? Theme.orange : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(Color(white: 0.27)))

            Spacer()

            Menu {
                Picker("Time of day", selection: $filter) {
                    ForEach(TimeFilter.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(filter.rawValue)
                    Image(systemName: "chevron.up")
                }
                .font(.subheadline)
                .foregroundStyle(Theme.label)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.background)
    }
}

struct CustomRangeSheet: View {
    @Binding var period: ReportPeriod
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $period.customFrom, displayedComponents: .date)
                DatePicker("To", selection: $period.customTo, in: period.customFrom..., displayedComponents: .date)
            }
            .navigationTitle("Custom Period")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
