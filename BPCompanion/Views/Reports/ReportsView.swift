import SwiftUI
import SwiftData
import UIKit

/// Reports: Blood Pressure (Summary, Trend, Range, Statistics) or Weight (Body Summary,
/// Weight Trend, Composition, Analysis, Weigh-ins), each as pages selected by swiping.
struct ReportsView: View {
    @Query(sort: \Reading.date) private var allReadings: [Reading]
    @ObservedObject private var bodyStore = BodyStore.shared

    private enum Kind: String, CaseIterable { case bp = "Blood Pressure", weight = "Weight" }
    @State private var kind: Kind = .bp
    @State private var weightPage = 0
    @State private var source: String?        // weight: nil = all apps

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
                Picker("Report", selection: $kind) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .readableWidth(600)

                PeriodHeader(period: $period)
                Theme.separator.frame(height: 4)

                switch kind {
                case .bp:
                    TabView(selection: $page) {
                        ForEach(0..<4, id: \.self) { i in
                            pageView(i).tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .never))
                case .weight:
                    WeightReportView(period: $period, source: $source, page: $weightPage)
                }

                Theme.separator.frame(height: 4)
                PeriodSelector(period: $period, filter: $filter, showCustom: $showCustom,
                               showsFilter: kind == .bp)
            }
            .background(Theme.background)
            .navigationTitle(kind == .bp ? titles[page] : WeightReportView.titles[weightPage])
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if kind == .bp {
                        Button(action: snapshot) {
                            Image(systemName: "camera").font(.title3)
                        }
                        .accessibilityLabel("Share snapshot")
                    } else if bodyStore.sources.count > 1 {
                        sourceMenu
                    }
                }
            }
            .orangeNavigationBar()
            .sheet(isPresented: $showCustom) {
                CustomRangeSheet(period: $period)
                    .presentationDetents([.large])
            }
            .sheet(item: $shareItem) { item in
                ActivityView(items: [item.image])
            }
        }
    }

    /// Weight report: show one scale app only (when several write body data).
    private var sourceMenu: some View {
        Menu {
            Picker("Source", selection: $source) {
                Text("All apps").tag(String?.none)
                ForEach(bodyStore.sources, id: \.self) { Text($0).tag(String?.some($0)) }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle").font(.title3)
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
        VStack(spacing: 4) {
            HStack {
                arrow("chevron.left", enabled: true) { period.shift(-1) }
                Spacer()
                column("From", period.from)
                Spacer()
                column("To", period.to)
                Spacer()
                arrow("chevron.right", enabled: period.canGoForward) { period.shift(1) }
            }
            // Looking at another window: one tap back to a window ending today.
            if showsArrows && !period.endsToday {
                Button {
                    withAnimation { period.goToToday() }
                } label: {
                    Label("Today", systemImage: "arrow.uturn.forward")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.orange))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
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
    /// The All / AM / PM menu (hidden in the Weight report).
    var showsFilter = true

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

            if showsFilter {
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.background)
    }
}

struct CustomRangeSheet: View {
    @Binding var period: ReportPeriod
    @Environment(\.dismiss) private var dismiss
    @State private var from: Date = .now
    @State private var to: Date = .now

    private var cal: Calendar { .current }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        quick("Today", cal.startOfDay(for: .now))
                        quick("This Week", cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now)
                        quick("This Month", cal.dateInterval(of: .month, for: .now)?.start ?? .now)
                    }
                    .listRowBackground(Color.clear)
                }
                Section("From") {
                    DatePicker("From", selection: $from, in: ...to, displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
                Section("To") {
                    DatePicker("To", selection: $to, in: from...max(from, Date.now), displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Custom Period")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        period.setCustom(from: from, to: to)
                        dismiss()
                    }
                }
            }
            .onAppear {
                from = period.customFrom
                to = min(period.customTo, .now)
            }
        }
    }

    /// Today / This Week / This Month: start of that period up to today, applied at once.
    private func quick(_ title: String, _ start: Date) -> some View {
        Button {
            period.setCustom(from: start, to: .now)
            dismiss()
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Capsule().fill(Theme.orange))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
