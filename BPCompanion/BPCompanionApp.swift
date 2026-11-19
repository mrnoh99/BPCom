import SwiftUI
import SwiftData
import UIKit

@main
struct BPCompanionApp: App {
    let container: ModelContainer
    @StateObject private var sync = CloudSyncMonitor.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let (container, cloudEnabled, setupError) = Self.makeContainer()
        self.container = container
        // Health writing is on by default (the permission sheet is shown on first launch).
        UserDefaults.standard.register(defaults: [SettingsKey.healthEnabled: true,
                                                  BodyStore.excludedSourcesKey: BodyStore.defaultExcludedSources,
                                                  SettingsKey.healthReadBody: true])
        CloudSyncMonitor.shared.configure(cloudEnabled: cloudEnabled, setupError: setupError)

        // Page dots on the Reports screen
        UIPageControl.appearance().currentPageIndicatorTintColor = UIColor(Theme.orange)
        UIPageControl.appearance().pageIndicatorTintColor = UIColor(white: 0.6, alpha: 1)
    }

    /// SwiftData store. When iCloud sync is enabled (Settings) the store is mirrored to the
    /// private CloudKit database of `CloudSyncMonitor.containerID`, so every device signed in
    /// with the same Apple ID sees the same readings. Existing local readings are uploaded
    /// the first time sync is turned on.
    static func makeContainer() -> (ModelContainer, cloudEnabled: Bool, setupError: String?) {
        let schema = Schema([Reading.self])
        let useCloud = UserDefaults.standard.object(forKey: SettingsKey.iCloudSync) as? Bool ?? true

        if useCloud {
            let config = ModelConfiguration(schema: schema,
                                            cloudKitDatabase: .private(CloudSyncMonitor.containerID))
            do {
                return (try ModelContainer(for: schema, configurations: config), true, nil)
            } catch {
                // e.g. iCloud capability not configured for this build – fall back to a local store.
                print("CloudKit container failed (\(error)); using local store")
                return (localContainer(schema), false, error.localizedDescription)
            }
        }
        return (localContainer(schema), false, nil)
    }

    private static func localContainer(_ schema: Schema) -> ModelContainer {
        do {
            return try ModelContainer(for: schema,
                                      configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none))
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.orange)
                .environmentObject(sync)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { sync.refreshAccount() }
        }
    }
}

enum SettingsKey {
    static let iCloudSync = "iCloudSyncEnabled"
    static let healthEnabled = "healthEnabled"
    static let healthReadBody = "healthReadBody"
    static let ownerName = "ownerName"
    static let defaultOwnerName = "Jaisung NOH"
}
