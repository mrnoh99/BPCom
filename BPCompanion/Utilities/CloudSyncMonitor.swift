import Foundation
import CoreData
import CloudKit
import Combine

/// Watches iCloud (CloudKit) sync done by SwiftData and exposes its state to the UI.
///
/// SwiftData mirrors the store with `NSPersistentCloudKitContainer`, which posts
/// `eventChangedNotification` for every setup / import / export it performs.
@MainActor
final class CloudSyncMonitor: ObservableObject {
    static let shared = CloudSyncMonitor()

    /// Must match `com.apple.developer.icloud-container-identifiers` in Config/BPCompanion.entitlements.
    static let containerID = "iCloud.com.jaisungnoh.BPCompanion"

    enum AccountState: Equatable {
        case checking, available, noAccount, restricted, temporarilyUnavailable, unknown

        var text: String {
            switch self {
            case .checking: return "Checking…"
            case .available: return "Signed in"
            case .noAccount: return "Not signed in"
            case .restricted: return "Restricted"
            case .temporarilyUnavailable: return "Temporarily unavailable"
            case .unknown: return "Unknown"
            }
        }
    }

    /// True when the ModelContainer was created with CloudKit mirroring.
    @Published private(set) var cloudEnabled = false
    /// Why CloudKit could not be enabled (e.g. capability not configured).
    @Published private(set) var setupError: String?
    @Published private(set) var account: AccountState = .checking
    @Published private(set) var syncing = false
    @Published private(set) var lastImport: Date?
    @Published private(set) var lastExport: Date?
    @Published private(set) var lastError: String?

    private var running = Set<UUID>()
    private var cancellables = Set<AnyCancellable>()

    private init() {
        NotificationCenter.default
            .publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.handle(note) }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: .CKAccountChanged)
            .merge(with: NotificationCenter.default.publisher(for: .NSUbiquityIdentityDidChange))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshAccount() }
            .store(in: &cancellables)
    }

    func configure(cloudEnabled: Bool, setupError: String?) {
        self.cloudEnabled = cloudEnabled
        self.setupError = setupError
        refreshAccount()
    }

    var lastSync: Date? {
        switch (lastImport, lastExport) {
        case let (i?, e?): return max(i, e)
        case let (i?, nil): return i
        case let (nil, e?): return e
        default: return nil
        }
    }

    func refreshAccount() {
        // Without an iCloud identity there is nothing to ask CloudKit.
        guard FileManager.default.ubiquityIdentityToken != nil else {
            account = .noAccount
            return
        }
        guard cloudEnabled else {
            account = .available
            return
        }
        Task {
            do {
                let status = try await CKContainer(identifier: Self.containerID).accountStatus()
                switch status {
                case .available: account = .available
                case .noAccount: account = .noAccount
                case .restricted: account = .restricted
                case .temporarilyUnavailable: account = .temporarilyUnavailable
                default: account = .unknown
                }
            } catch {
                account = .unknown
                lastError = error.localizedDescription
            }
        }
    }

    private func handle(_ note: Notification) {
        guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }

        if event.endDate == nil {
            running.insert(event.identifier)
        } else {
            running.remove(event.identifier)
            if let error = event.error {
                lastError = Self.describe(error)
            } else {
                lastError = nil
                switch event.type {
                case .import: lastImport = event.endDate
                case .export: lastExport = event.endDate
                default: break
                }
            }
        }
        syncing = !running.isEmpty
    }

    private static func describe(_ error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .notAuthenticated: return "Sign in to iCloud in the Settings app."
            case .quotaExceeded: return "iCloud storage is full."
            case .networkUnavailable, .networkFailure: return "No network connection. Will retry automatically."
            default: break
            }
        }
        return error.localizedDescription
    }
}
