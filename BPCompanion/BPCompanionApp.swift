import SwiftUI
import SwiftData
import UIKit

@main
struct BPCompanionApp: App {
    let container: ModelContainer

    init() {
        container = Self.makeContainer()

        // Page dots on the Reports screen
        UIPageControl.appearance().currentPageIndicatorTintColor = UIColor(Theme.orange)
        UIPageControl.appearance().pageIndicatorTintColor = UIColor(white: 0.6, alpha: 1)
    }

    /// SwiftData store. When iCloud sync is enabled (Settings) the store is mirrored
    /// to the private CloudKit database of the container listed in the entitlements.
    static func makeContainer() -> ModelContainer {
        let schema = Schema([Reading.self])
        let useCloud = UserDefaults.standard.object(forKey: SettingsKey.iCloudSync) as? Bool ?? true
        let config = ModelConfiguration(schema: schema,
                                        cloudKitDatabase: useCloud ? .automatic : .none)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            // e.g. iCloud capability not configured for this build – fall back to a local store.
            print("CloudKit container failed (\(error)); using local store")
            let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: local)
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.orange)
        }
        .modelContainer(container)
    }
}

enum SettingsKey {
    static let iCloudSync = "iCloudSyncEnabled"
    static let ownerName = "ownerName"
    static let defaultOwnerName = "Jaisung NOH"
}
