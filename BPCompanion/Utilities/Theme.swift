import SwiftUI

/// Orange colour scheme for the whole app.
enum Theme {
    // Brand
    static let orange = Color(red: 1.00, green: 0.55, blue: 0.10)       // #FF8C1A
    static let orangeDeep = Color(red: 0.93, green: 0.42, blue: 0.05)   // #ED6B0D
    static let orangeLight = Color(red: 1.00, green: 0.72, blue: 0.40)  // #FFB866
    static let header = orangeDeep

    // Surfaces (dark, like the reference screens)
    static let background = Color(red: 0.17, green: 0.17, blue: 0.17)
    static let cell = Color(red: 0.20, green: 0.20, blue: 0.20)
    static let cellHeader = Color(red: 0.24, green: 0.22, blue: 0.20)
    static let gridLine = Color(red: 0.32, green: 0.32, blue: 0.32)
    static let separator = Color.black
    static let tabBar = Color(red: 0.11, green: 0.11, blue: 0.11)

    // Text
    static let label = orange
    static let primaryText = Color.white
    static let secondaryText = Color(white: 0.75)

    // Value levels
    static let low = Color(red: 0.25, green: 0.55, blue: 1.00)
    static let normal = Color(red: 0.30, green: 0.80, blue: 0.30)
    static let elevated = Color(red: 1.00, green: 0.70, blue: 0.10)
    static let high = Color(red: 1.00, green: 0.23, blue: 0.19)

    // Chart series
    static let systolicLine = Color(red: 0.40, green: 0.70, blue: 1.00)
    static let diastolicLine = Color(red: 0.85, green: 0.40, blue: 0.95)
    static let pulseLine = Color(red: 1.00, green: 0.60, blue: 0.20)
    static let weightLine = Color(red: 0.35, green: 0.85, blue: 0.70)

    // Add Entry sheet
    static let sheetGradient = LinearGradient(
        colors: [Color(red: 0.98, green: 0.58, blue: 0.18), Color(red: 0.90, green: 0.42, blue: 0.08)],
        startPoint: .top, endPoint: .bottom)

    static func color(for level: BPLevel) -> Color {
        switch level {
        case .low: return low
        case .normal: return normal
        case .elevated: return elevated
        case .high: return high
        }
    }
}

extension View {
    /// On iPad (and other wide screens) keeps tables/lists at a readable width, centered.
    func readableWidth(_ max: CGFloat = 820) -> some View {
        frame(maxWidth: max)
            .frame(maxWidth: .infinity)
    }

    /// iOS/iPadOS 26 blurs content that scrolls under the top bar ("scroll edge effect").
    /// With the tab bar merged into the navigation bar on iPad/Mac that blur covers the
    /// first rows of the list, so it is turned off at the top. No-op on older systems.
    @ViewBuilder
    func noTopScrollBlur() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Orange navigation bar with white title/buttons.
    func orangeNavigationBar() -> some View {
        self
            .toolbarBackground(Theme.header, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
