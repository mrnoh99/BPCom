import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Reading.date, order: .reverse) private var readings: [Reading]
    @AppStorage(SettingsKey.ownerName) private var ownerName = SettingsKey.defaultOwnerName

    @State private var editMode: EditMode = .inactive
    @State private var collapsed: Set<String> = []
    @State private var showAdd = false
    @State private var editing: Reading?

    private struct MonthSection: Identifiable {
        let id: String
        let title: String
        let readings: [Reading]
    }

    private var sections: [MonthSection] {
        let cal = Calendar.current
        var order: [String] = []
        var groups: [String: [Reading]] = [:]
        var titles: [String: String] = [:]
        for r in readings {
            let c = cal.dateComponents([.year, .month], from: r.date)
            let key = String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
            if groups[key] == nil {
                order.append(key)
                titles[key] = Fmt.month(r.date)
            }
            groups[key, default: []].append(r)
        }
        return order.map { MonthSection(id: $0, title: titles[$0] ?? $0, readings: groups[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if readings.isEmpty {
                    ContentUnavailableView("No Readings",
                                           systemImage: "list.bullet.clipboard",
                                           description: Text("Tap + to add a blood pressure reading."))
                } else {
                    list
                }
            }
            .background(Theme.background)
            .navigationTitle(ownerName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    } label: {
                        Image(systemName: editMode.isEditing ? "checkmark.circle" : "pencil.circle")
                            .font(.title2)
                    }
                    .accessibilityLabel(editMode.isEditing ? "Done" : "Edit")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle").font(.title2)
                    }
                    .accessibilityLabel("Add Entry")
                }
            }
            .orangeNavigationBar()
            .environment(\.editMode, $editMode)
            .sheet(isPresented: $showAdd) {
                AddEntryView(editing: nil, template: readings.first)
            }
            .sheet(item: $editing) { r in
                AddEntryView(editing: r, template: nil)
            }
        }
    }

    private var list: some View {
        List {
            ForEach(sections) { section in
                Section {
                    if !collapsed.contains(section.id) {
                        ForEach(section.readings) { r in
                            Button { editing = r } label: { HistoryRow(reading: r) }
                                .buttonStyle(.plain)
                                .listRowBackground(Theme.background)
                                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                                .listRowSeparatorTint(Theme.gridLine)
                        }
                        .onDelete { offsets in
                            for i in offsets { context.delete(section.readings[i]) }
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
        .background(Theme.background)
    }
}

struct HistoryRow: View {
    let reading: Reading

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CalendarBadge(date: reading.date)

            VStack(alignment: .leading, spacing: 4) {
                (Text("\(reading.systolic)").foregroundColor(Theme.color(for: reading.systolicLevel))
                 + Text("/").foregroundColor(Theme.primaryText)
                 + Text("\(reading.diastolic)").foregroundColor(Theme.color(for: reading.diastolicLevel))
                 + Text(" mmHg").font(.subheadline).foregroundColor(Theme.primaryText))
                    .font(.title3)
                Text("\(reading.pulse) bpm")
                    .font(.subheadline)
                Text("MAP: \(Fmt.int(reading.map)) mmHg")
                    .font(.subheadline)
            }
            .foregroundStyle(Theme.primaryText)

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                Text(Fmt.time(reading.date))
                if let w = reading.weight {
                    Text("\(Fmt.weight(w)) kg")
                } else {
                    Text(" ")
                }
                HStack(spacing: 4) {
                    if reading.starred {
                        Image(systemName: "star.fill").foregroundStyle(Theme.elevated)
                    }
                    if !reading.note.isEmpty {
                        Image(systemName: "note.text").foregroundStyle(Theme.secondaryText)
                    }
                    if reading.drug {
                        Image(systemName: "pills.fill").foregroundStyle(Theme.high)
                    }
                }
                .font(.caption)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.primaryText)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .contentShape(Rectangle())
    }
}

/// Small calendar-page icon with the day of month.
struct CalendarBadge: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Theme.orange.frame(height: 12)
            Text(date.formatted(.dateTime.day()))
                .font(.title2)
                .foregroundStyle(Theme.orangeDeep)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
        }
        .frame(width: 48, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
