import SwiftUI
import SwiftData

/// "+" screen: Basic (BP / pulse / date) and Note tabs.
/// Body weight is not entered here — it comes from Apple Health (e.g. YUNMAI) in the Body tab.
/// Also used to edit an existing reading from History.
struct AddEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private let editing: Reading?

    private enum Tab: String, CaseIterable { case basic = "Basic", note = "Note" }
    private enum BasicPicker { case values, date }

    @State private var tab: Tab = .basic
    @State private var basicPicker: BasicPicker = .values

    @State private var systolic: Int?
    @State private var diastolic: Int?
    @State private var pulse: Int?
    @State private var date: Date
    @State private var drug: Bool

    @State private var note: String
    @State private var starred: Bool
    @State private var confirmDelete = false
    @FocusState private var noteFocused: Bool

    // Defaults when nothing was recorded before
    private static let defaultSys = 120, defaultDia = 80, defaultPulse = 70

    /// - Parameters:
    ///   - editing: reading to edit, or `nil` to add a new one.
    ///   - template: latest reading, used to pre-fill a new entry (like the reference app).
    init(editing: Reading?, template: Reading?) {
        self.editing = editing
        let src = editing ?? template
        _systolic = State(initialValue: src?.systolic ?? Self.defaultSys)
        _diastolic = State(initialValue: src?.diastolic ?? Self.defaultDia)
        _pulse = State(initialValue: src?.pulse ?? Self.defaultPulse)
        _date = State(initialValue: editing?.date ?? .now)
        _drug = State(initialValue: src?.drug ?? false)

        _note = State(initialValue: editing?.note ?? "")
        _starred = State(initialValue: editing?.starred ?? false)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabBar
                ZStack {
                    Theme.sheetGradient.ignoresSafeArea()
                    VStack(spacing: 0) {
                        switch tab {
                        case .basic: basicTab
                        case .note: noteTab
                        }
                    }
                }
            }
            .background(Theme.sheetGradient.ignoresSafeArea())
            .navigationTitle(editing == nil ? "Add Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(systolic == nil || diastolic == nil)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .foregroundStyle(.white)
            .tint(.white)
            .confirmationDialog("Delete this reading?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let editing {
                        HealthSync.shared.remove(ids: [editing.id])
                        context.delete(editing)
                    }
                    dismiss()
                }
            }
        }
        .presentationBackground(Theme.orangeDeep)
    }

    // MARK: Tabs header

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        tab = t
                        noteFocused = (t == .note)
                    }
                } label: {
                    VStack(spacing: 8) {
                        Text(t.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(tab == t ? .white : .white.opacity(0.6))
                        Rectangle()
                            .fill(tab == t ? Color.white : .clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Basic

    private var basicTab: some View {
        VStack(spacing: 0) {
            card {
                VStack(spacing: 26) {
                    HStack {
                        Spacer().frame(width: 24)
                        Spacer()
                        Text("\(systolic.map(String.init) ?? "---")/\(diastolic.map(String.init) ?? "---")")
                            .font(.system(size: 40, weight: .regular))
                            .monospacedDigit()
                        Spacer()
                        clearButton { systolic = nil; diastolic = nil; basicPicker = .values }
                    }
                    HStack {
                        Spacer().frame(width: 24)
                        Spacer()
                        (Text(pulse.map(String.init) ?? "--").font(.title2)
                         + Text(" bpm").font(.subheadline))
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                        clearButton { pulse = nil; basicPicker = .values }
                    }
                    Text(Fmt.dateTime(date))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .onTapGesture { basicPicker = .date }
                }
                .padding(.vertical, 30)
            }

            HStack {
                pickerModeToggle
                Spacer()
                Toggle(isOn: $drug) {
                    Text("Drug").font(.title3)
                }
                .toggleStyle(SwitchToggleStyle(tint: Theme.orangeLight))
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.top, 30)

            if editing != nil {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete Reading", systemImage: "trash")
                        .font(.subheadline)
                }
                .tint(.white)
                .padding(.top, 14)
            }

            Spacer(minLength: 8)

            wheelArea {
                switch basicPicker {
                case .values: bpWheels
                case .date:
                    DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var pickerModeToggle: some View {
        HStack(spacing: 0) {
            modeButton(.values, systemImage: "heart.fill", color: .red)
            modeButton(.date, systemImage: "clock", color: Theme.orangeDeep)
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.25)))
        .overlay(Capsule().stroke(.white.opacity(0.8), lineWidth: 1))
    }

    private func modeButton(_ mode: BasicPicker, systemImage: String, color: Color) -> some View {
        Button {
            basicPicker = mode
        } label: {
            Image(systemName: systemImage)
                .foregroundStyle(basicPicker == mode ? color : .white)
                .frame(width: 44, height: 26)
                .background(Capsule().fill(basicPicker == mode ? Color.white : .clear))
        }
        .buttonStyle(.plain)
    }

    private var bpWheels: some View {
        HStack(spacing: 0) {
            wheel(Binding(get: { systolic ?? Self.defaultSys }, set: { systolic = $0 }), 50...260)
            unit("mmHg")
            wheel(Binding(get: { diastolic ?? Self.defaultDia }, set: { diastolic = $0 }), 30...180)
            unit("mmHg")
            wheel(Binding(get: { pulse ?? Self.defaultPulse }, set: { pulse = $0 }), 30...220)
            unit("bpm")
        }
    }

    // MARK: Note

    private var noteTab: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                card {
                    TextEditor(text: $note)
                        .focused($noteFocused)
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(.white)
                        .padding(8)
                        .frame(height: 200)
                }
                Button { starred.toggle() } label: {
                    Image(systemName: starred ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(starred ? Color.yellow : .white)
                }
                .padding(.top, 2)
                .padding(.trailing, 2)
                .accessibilityLabel("Star")
            }
            Spacer()
        }
    }

    // MARK: Building blocks

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.75), lineWidth: 1))
            .padding(.horizontal, 10)
            .padding(.top, 34)
    }

    private func clearButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Theme.orangeDeep, .white)
                .font(.title3)
        }
        .buttonStyle(.plain)
        .frame(width: 24)
        .padding(.trailing, 12)
        .accessibilityLabel("Clear")
    }

    private func wheelArea<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .background(Color.black.ignoresSafeArea(edges: .bottom))
            .environment(\.colorScheme, .dark)
    }

    private func wheel(_ selection: Binding<Int>, _ range: ClosedRange<Int>, prefix: String = "") -> some View {
        Picker("", selection: selection) {
            ForEach(range, id: \.self) { v in
                Text("\(prefix)\(v)").tag(v)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private func unit(_ s: String) -> some View {
        Text(s).font(.subheadline).foregroundStyle(.white).fixedSize()
    }

    // MARK: Save

    private func save() {
        guard let s = systolic, let d = diastolic else { return }
        let p = pulse ?? 0
        if let r = editing {
            r.systolic = s
            r.diastolic = d
            r.pulse = p
            r.date = date
            r.drug = drug
            r.note = note
            r.starred = starred
            try? context.save()
            HealthSync.shared.upsert([r])
        } else {
            let r = Reading(date: date, systolic: s, diastolic: d, pulse: p,
                            drug: drug, note: note, starred: starred)
            context.insert(r)
            try? context.save()
            HealthSync.shared.upsert([r])
        }
        dismiss()
    }
}
