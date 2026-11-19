import SwiftUI

struct RootView: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)
            HistoryView()
                .tabItem { Label("History", systemImage: "list.bullet") }
                .tag(1)
            ReportsView()
                .tabItem { Label("Reports", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(3)
        }
        .toolbarBackground(Theme.tabBar, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
