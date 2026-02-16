import DeviceActivity
import ManagedSettings
import FamilyControls
import Foundation
import os

// MARK: - DeviceActivityMonitorExtension

/// Extension point that receives callbacks from the system when monitored
/// `DeviceActivitySchedule` intervals start, end, or when usage thresholds
/// fire.
///
/// Runs in a separate process from the main ScreenBreak app. Communication
/// with the main app happens through a shared `UserDefaults` suite
/// (`group.com.screenbreak.app`) where the `FamilyActivitySelection` is
/// persisted as JSON-encoded `Data`.
///
/// The principal class name **must** match the `NSExtensionPrincipalClass`
/// value in `Info.plist` (`$(PRODUCT_MODULE_NAME).DeviceActivityMonitorExtension`).
class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    // MARK: - Constants

    /// Shared App Group suite name -- must match the entitlements and the
    /// main app's `ScreenTimeManager.suiteName`.
    private static let appGroupID = "group.com.screenbreak.app"

    /// UserDefaults key under which the main app persists the encoded
    /// `FamilyActivitySelection`. Must match `ScreenTimeManager.selectionKey`.
    private static let selectionKey = "screenbreak.familyActivitySelection"

    // MARK: - Dependencies

    /// Each extension process gets its own `ManagedSettingsStore` instance.
    /// Writes to this store are immediately reflected system-wide.
    private let store = ManagedSettingsStore()

    private let logger = Logger(
        subsystem: "com.screenbreak.app.DeviceActivityMonitorExtension",
        category: "DeviceActivityMonitor"
    )

    // MARK: - Interval Lifecycle

    /// Called by the system when a monitored `DeviceActivitySchedule` interval
    /// begins (e.g. midnight for the "screenbreak.daily" schedule).
    ///
    /// We re-apply shielding here to ensure that even if the main app was
    /// terminated or the device rebooted, the user's blocked-app selection
    /// is enforced as soon as the new monitoring window opens.
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        logger.info("intervalDidStart for activity: \(activity.rawValue)")

        applyShieldingFromSharedDefaults()
    }

    /// Called by the system when the monitored interval ends (e.g. 23:59 for
    /// the daily schedule).
    ///
    /// We intentionally keep shields in place rather than removing them.
    /// The schedule repeats daily, so a brief gap between 23:59 and 00:00 is
    /// acceptable. Removing shields here would leave a window where blocked
    /// apps are accessible.
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        logger.info("intervalDidEnd for activity: \(activity.rawValue)")

        // Re-apply to ensure continuous coverage across the interval boundary.
        applyShieldingFromSharedDefaults()
    }

    // MARK: - Threshold Events

    /// Called when a `DeviceActivityEvent` threshold is reached (e.g. a
    /// temporary unlock timer expired, implemented as a usage-time event).
    ///
    /// This is used as a server-side backstop: if the main app's in-process
    /// relock `Timer` did not fire (app killed, etc.), the system will call
    /// this method and we re-apply shields.
    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        logger.info("eventDidReachThreshold: \(event.rawValue) for activity: \(activity.rawValue)")

        // Re-shield everything -- the temporary unlock window has elapsed.
        applyShieldingFromSharedDefaults()
    }

    // MARK: - Warnings

    /// Called shortly before the interval is about to start. Can be used to
    /// prepare resources or pre-warm caches.
    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
        logger.info("intervalWillStartWarning for activity: \(activity.rawValue)")
    }

    /// Called shortly before the interval is about to end.
    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        logger.info("intervalWillEndWarning for activity: \(activity.rawValue)")
    }

    // MARK: - Private Helpers

    /// Reads the saved `FamilyActivitySelection` from the shared App Group
    /// `UserDefaults`, decodes it, and writes the corresponding application
    /// and category tokens into the `ManagedSettingsStore` so the system
    /// shields those apps.
    private func applyShieldingFromSharedDefaults() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else {
            logger.error("Failed to open shared UserDefaults suite: \(Self.appGroupID)")
            return
        }

        guard let data = defaults.data(forKey: Self.selectionKey) else {
            logger.info("No saved FamilyActivitySelection found in shared defaults -- clearing shields.")
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            store.shield.webDomainCategories = nil
            return
        }

        let selection: FamilyActivitySelection
        do {
            selection = try JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        } catch {
            logger.error("Failed to decode FamilyActivitySelection: \(error.localizedDescription)")
            return
        }

        let appTokens = selection.applicationTokens
        let categoryTokens = selection.categoryTokens
        let webDomainTokens = selection.webDomainTokens
        let webCategoryTokens = selection.categoryTokens

        // Apply application shields.
        if appTokens.isEmpty {
            store.shield.applications = nil
            logger.info("No application tokens to shield -- cleared application shields.")
        } else {
            store.shield.applications = .specific(appTokens)
            logger.info("Shielding \(appTokens.count) application(s).")
        }

        // Apply category shields.
        if categoryTokens.isEmpty {
            store.shield.applicationCategories = nil
        } else {
            store.shield.applicationCategories = .specific(categoryTokens)
            logger.info("Shielding \(categoryTokens.count) app category/categories.")
        }

        // Apply web domain shields.
        if webDomainTokens.isEmpty {
            store.shield.webDomains = nil
        } else {
            store.shield.webDomains = .specific(webDomainTokens)
            logger.info("Shielding \(webDomainTokens.count) web domain(s).")
        }

        // Apply web domain category shields.
        if webCategoryTokens.isEmpty {
            store.shield.webDomainCategories = nil
        } else {
            store.shield.webDomainCategories = .specific(webCategoryTokens)
        }
    }
}
