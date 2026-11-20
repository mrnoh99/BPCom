import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    @State private var pendingImport: URL?
    @State private var showImportDialog = false
    @State private var importMessage: String?

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .noTopScrollBlur()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)
            HistoryView()
                .noTopScrollBlur()
                .tabItem { Label("History", systemImage: "list.bullet") }
                .tag(1)
            ReportsView()
                .noTopScrollBlur()
                .tabItem { Label("Reports", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(2)
            BodyView()
                .noTopScrollBlur()
                .tabItem { Label("Body", systemImage: "figure") }
                .tag(4)
            SettingsView()
                .noTopScrollBlur()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(3)
        }
        .toolbarBackground(Theme.tabBar, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onAppear { BodyStore.shared.attach(context) }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                BodyStore.shared.attach(context)
                Task { await HealthSync.shared.onBecameActive(context) }
            }
        }
        // A .csv opened from Files / Mail / KakaoTalk / share sheet ("Open in BP Companion")
        .onOpenURL { url in
            guard url.isFileURL else { return }
            pendingImport = url
            showImportDialog = true
        }
        .confirmationDialog("Import blood pressure data?",
                            isPresented: $showImportDialog,
                            titleVisibility: .visible,
                            presenting: pendingImport) { url in
            Button("Import") {
                do {
                    if YunmaiImport.looksLikeYunmaiFile(url) {
                        importMessage = try YunmaiImport.importFile(at: url, into: context).message
                        Task { await BodyStore.shared.refresh() }
                    } else {
                        importMessage = try CSVImporter.importFile(at: url, into: context)
                    }
                    tab = 1
                } catch {
                    importMessage = "Import failed: \(error.localizedDescription)"
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { url in
            Text(url.lastPathComponent)
        }
        .alert("BP Companion",
               isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }
}
