import SwiftUI
import SwiftData

/// "+" screen: Basic (BP / pulse / date), Weight and Note tabs.
/// Also used to edit an existing reading from History.
struct AddEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private let editing: Reading?

    private enum Tab: String, CaseIterable { case basic = "Basic", weight = "Weight", note = "Note" }
    private enum BasicPicker { case values, date }

    @State private var tab: Tab = .basic
    @State private var basicPicker: BasicPicker = .values

    @State private var systolic: Int?
    @State private var diastolic: Int?
    @State private var pulse: Int?
    @State private var date: Date
    @State private var drug: Bool

    @State private var weightWhole: Int
    @State private var weightTenth: Int
    @State private var hasWeight: Bool

    @State private var note: String
    @State private var starred: Bool
    @State private var confirmDelete = false
    @FocusState private var noteFocused: Bool

    // Defaults when nothing was recorded before
    private static let defaultSys = 120, defaultDia = 80, defaultPulse = 70, defaultWeight = 70.0

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

        let w = src?.weight ?? Self.defaultWeight
        let tenths = Int((w * 10).rounded())
        _weightWhole = State(initialValue: tenths / 10)
        _weightTenth = State(initialValue: tenths % 10)
        _hasWeight = State(initialValue: src?.weight != nil)

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
                        case .weight: weightTab
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

    // MARK: Weight

    private var weightTab: some View {
        VStack(spacing: 0) {
            card {
                ZStack {
                    ScaleDial(value: Double(weightWhole) + Double(weightTenth) / 10)
                        .stroke(.white.opacity(0.35), lineWidth: 1.5)
                        .frame(height: 70)
                        .frame(maxHeight: .infinity, alignment: .top)
                    Rectangle()
                        .fill(.white.opacity(0.35))
                        .frame(width: 1.5)
                    HStack {
                        Spacer().frame(width: 24)
                        Spacer()
                        VStack(spacing: 14) {
                            Text(hasWeight ? "\(weightWhole).\(weightTenth)" : "--.-")
                                .font(.system(size: 30))
                                .monospacedDigit()
                            Text("kg").font(.subheadline)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Theme.orangeDeep.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                        Spacer()
                        clearButton { hasWeight = false }
                    }
                    .padding(.top, 50)
                }
                .frame(height: 200)
            }

            Spacer(minLength: 8)

            wheelArea {
                HStack(spacing: 0) {
                    wheel(Binding(get: { weightWhole }, set: { weightWhole = $0; hasWeight = true }), 20...250)
                    wheel(Binding(get: { weightTenth }, set: { weightTenth = $0; hasWeight = true }), 0...9, prefix: ".")
                    unit("kg")
                }
            }
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
        let w: Double? = hasWeight ? Double(weightWhole) + Double(weightTenth) / 10 : nil
        if let r = editing {
            r.systolic = s
            r.diastolic = d
            r.pulse = p
            r.date = date
            r.weight = w
            r.drug = drug
            r.note = note
            r.starred = starred
            try? context.save()
            HealthSync.shared.upsert([r])
        } else {
            let r = Reading(date: date, systolic: s, diastolic: d, pulse: p,
                            weight: w, drug: drug, note: note, starred: starred)
            context.insert(r)
            try? context.save()
            HealthSync.shared.upsert([r])
        }
        dismiss()
    }
}

/// Bathroom-scale style tick arc drawn at the top of the Weight card.
/// The ticks scroll with the value so the dial "moves" as the wheel turns.
struct ScaleDial: Shape {
    var value: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.maxY + rect.width * 0.9)
        let radius = rect.width * 0.9 + rect.height * 0.55
        let stepDeg = 1.6               // degrees per 0.5 kg
        let offset = (value * 2).truncatingRemainder(dividingBy: 1) * stepDeg
        let span = 34.0
        var a = -span - offset
        var i = Int((value * 2).rounded(.down)) - Int(span / stepDeg)
        while a <= span {
            let rad = (a - 90) * .pi / 180
            let long = i % 10 == 0
            let mid = i % 2 == 0
            let len = long ? rect.height * 0.55 : (mid ? rect.height * 0.35 : rect.height * 0.22)
            let outer = CGPoint(x: center.x + cos(rad) * radius, y: center.y + sin(rad) * radius)
            let inner = CGPoint(x: center.x + cos(rad) * (radius - len), y: center.y + sin(rad) * (radius - len))
            p.move(to: outer)
            p.addLine(to: inner)
            a += stepDeg
            i += 1
        }
        return p
    }
}
