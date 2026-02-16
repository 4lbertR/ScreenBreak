import DeviceActivity
import ManagedSettings
import FamilyControls
import Foundation
import os

// MARK: - DeviceActivityMonitorExtension

class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private static let appGroupID = "group.albertreinman.app"
    private static let selectionKey = "screenbreak.familyActivitySelection"

    private let store = ManagedSettingsStore()

    private let logger = Logger(
        subsystem: "com.screenbreak.app.DeviceActivityMonitorExtension",
        category: "DeviceActivityMonitor"
    )

    // MARK: - Interval Lifecycle

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        logger.info("intervalDidStart for activity: \(activity.rawValue, privacy: .public)")
        applyShieldingFromSharedDefaults()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        logger.info("intervalDidEnd for activity: \(activity.rawValue, privacy: .public)")
        applyShieldingFromSharedDefaults()
    }

    // MARK: - Threshold Events

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        logger.info("eventDidReachThreshold: \(event.rawValue, privacy: .public)")
        applyShieldingFromSharedDefaults()
    }

    // MARK: - Warnings

    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
    }

    // MARK: - Private Helpers

    private func applyShieldingFromSharedDefaults() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else {
            return
        }

        guard let data = defaults.data(forKey: Self.selectionKey) else {
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
            logger.error("Failed to decode FamilyActivitySelection")
            return
        }

        let appTokens = selection.applicationTokens
        let categoryTokens = selection.categoryTokens
        let webDomainTokens = selection.webDomainTokens

        store.shield.applications = appTokens.isEmpty ? nil : appTokens
        store.shield.webDomains = webDomainTokens.isEmpty ? nil : webDomainTokens

        if categoryTokens.isEmpty {
            store.shield.applicationCategories = nil
            store.shield.webDomainCategories = nil
        } else {
            store.shield.applicationCategories = .specific(categoryTokens)
            store.shield.webDomainCategories = .specific(categoryTokens)
        }
    }
}
