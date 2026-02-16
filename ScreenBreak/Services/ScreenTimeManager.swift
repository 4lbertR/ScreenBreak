import FamilyControls
import ManagedSettings
import DeviceActivity
import SwiftData
import Foundation
import os

// MARK: - ScreenTimeManager

/// Central service responsible for managing app blocking via Apple's Screen Time APIs.
///
/// Uses `ManagedSettingsStore` to apply and remove application shields, `DeviceActivityCenter`
/// for scheduling monitoring intervals, and `AuthorizationCenter` for requesting user consent.
///
/// Designed as a singleton accessed via `ScreenTimeManager.shared`. All shield mutations
/// happen on the main actor to avoid data races with SwiftUI observation.
@Observable
@MainActor
final class ScreenTimeManager {

    // MARK: - Singleton

    static let shared = ScreenTimeManager()

    // MARK: - Published State

    /// The current Screen Time / FamilyControls authorization status.
    var authorizationStatus: AuthorizationStatus = .notDetermined

    /// The user's current selection of apps and categories to block.
    var selectedApps: FamilyActivitySelection = FamilyActivitySelection()

    /// Whether device activity monitoring is currently active.
    var isMonitoring: Bool = false

    /// Set of app tokens that are temporarily unshielded (mid-unlock).
    var activeUnlocks: Set<ApplicationToken> = []

    // MARK: - Private

    private let store = ManagedSettingsStore()
    private let center = AuthorizationCenter.shared
    private let deviceActivityCenter = DeviceActivityCenter()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ScreenBreak",
                                category: "ScreenTimeManager")

    /// Timers keyed by the hash of the application token, used to schedule re-shielding.
    private var relockTimers: [Int: Timer] = [:]

    /// UserDefaults key for the persisted `FamilyActivitySelection`.
    private static let selectionKey = "screenbreak.familyActivitySelection"

    /// App group suite for sharing with extensions (DeviceActivity monitor, shield config, etc.).
    private static let suiteName = "group.com.screenbreak.app"

    // MARK: - Init

    private init() {
        loadSelection()
        authorizationStatus = center.authorizationStatus
    }

    // MARK: - Authorization

    /// Requests FamilyControls authorization from the user.
    ///
    /// On iOS 17+ this presents the system authorization prompt. The method is `async throws`
    /// because it suspends until the user responds and may throw if denied or unavailable.
    func requestAuthorization() async throws {
        do {
            try await center.requestAuthorization(for: .individual)
            authorizationStatus = center.authorizationStatus
            logger.info("FamilyControls authorization granted.")
        } catch {
            authorizationStatus = center.authorizationStatus
            logger.error("FamilyControls authorization failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Shielding

    /// Applies shields to **all** currently-selected applications, minus any that are
    /// temporarily unlocked.
    ///
    /// This writes to the `ManagedSettingsStore` which immediately causes the system to
    /// overlay a shield on every listed app.
    func applyShielding() {
        let tokensToShield = selectedApps.applicationTokens.subtracting(activeUnlocks)
        guard !tokensToShield.isEmpty else {
            store.shield.applications = nil
            logger.info("No apps to shield — cleared shield configuration.")
            return
        }
        store.shield.applications = tokensToShield
        store.shield.applicationCategories = selectedApps.categoryTokens.isEmpty
            ? nil
            : .specific(selectedApps.categoryTokens)
        logger.info("Shielding applied to \(tokensToShield.count) app(s).")
    }

    /// Removes **all** shields, effectively unblocking every app.
    func removeShielding() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
        logger.info("All shields removed.")
    }

    /// Removes the shield for a single app token so the user can open it.
    ///
    /// - Parameter token: The `ApplicationToken` to temporarily unshield.
    func removeShieldingForApp(token: ApplicationToken) {
        activeUnlocks.insert(token)
        applyShielding()
        logger.info("Shield removed for single app token.")
    }

    /// Re-applies the shield for a specific app token after an unlock window expires.
    ///
    /// - Parameter token: The `ApplicationToken` to re-shield.
    func reapplyShieldingForApp(token: ApplicationToken) {
        activeUnlocks.remove(token)
        applyShielding()
        logger.info("Shield re-applied for single app token.")
    }

    // MARK: - Temporary Unlock

    /// Temporarily unblocks a specific app for the given duration, then automatically
    /// re-shields it when the timer fires.
    ///
    /// - Parameters:
    ///   - token: The application token to unlock.
    ///   - duration: Access window in seconds (typically 900 for 15 min).
    func temporarilyUnlockApp(token: ApplicationToken, duration: TimeInterval) {
        // Cancel any existing relock timer for this token.
        let key = token.hashValue
        relockTimers[key]?.invalidate()

        // Remove shield immediately.
        removeShieldingForApp(token: token)

        // Schedule re-shielding.
        let timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reapplyShieldingForApp(token: token)
                self.relockTimers.removeValue(forKey: key)
                self.logger.info("Relock timer fired — app re-shielded after \(Int(duration))s.")
            }
        }
        // Ensure the timer fires even when the scroll view / tracking run loop mode is active.
        RunLoop.main.add(timer, forMode: .common)
        relockTimers[key] = timer

        logger.info("App temporarily unlocked for \(Int(duration)) seconds.")
    }

    /// Cancels the relock timer for an app (e.g. if the user manually re-locks early).
    func cancelRelockTimer(for token: ApplicationToken) {
        let key = token.hashValue
        relockTimers[key]?.invalidate()
        relockTimers.removeValue(forKey: key)
    }

    // MARK: - Device Activity Monitoring

    /// Starts a recurring daily monitoring schedule via `DeviceActivityCenter`.
    ///
    /// The schedule covers the full day (midnight to 23:59) and repeats. The companion
    /// `DeviceActivityMonitor` extension will receive callbacks when intervals start/end.
    func startMonitoring() {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        let activityName = DeviceActivityName("screenbreak.daily")

        do {
            try deviceActivityCenter.startMonitoring(activityName, during: schedule)
            isMonitoring = true
            logger.info("Device activity monitoring started.")
        } catch {
            isMonitoring = false
            logger.error("Failed to start monitoring: \(error.localizedDescription)")
        }
    }

    /// Stops all device activity monitoring.
    func stopMonitoring() {
        deviceActivityCenter.stopMonitoring()
        isMonitoring = false
        logger.info("Device activity monitoring stopped.")
    }

    // MARK: - Persistence

    /// Persists the current `FamilyActivitySelection` to `UserDefaults` (app group suite)
    /// so it survives app restarts and is available to extensions.
    func saveSelection() {
        do {
            let data = try JSONEncoder().encode(selectedApps)
            let defaults = UserDefaults(suiteName: Self.suiteName) ?? .standard
            defaults.set(data, forKey: Self.selectionKey)
            logger.info("FamilyActivitySelection saved (\(self.selectedApps.applicationTokens.count) app(s)).")
        } catch {
            logger.error("Failed to save FamilyActivitySelection: \(error.localizedDescription)")
        }
    }

    /// Loads a previously-saved `FamilyActivitySelection` from `UserDefaults`.
    func loadSelection() {
        let defaults = UserDefaults(suiteName: Self.suiteName) ?? .standard
        guard let data = defaults.data(forKey: Self.selectionKey) else {
            logger.info("No saved FamilyActivitySelection found.")
            return
        }
        do {
            selectedApps = try JSONDecoder().decode(FamilyActivitySelection.self, from: data)
            logger.info("FamilyActivitySelection loaded (\(self.selectedApps.applicationTokens.count) app(s)).")
        } catch {
            logger.error("Failed to decode saved FamilyActivitySelection: \(error.localizedDescription)")
        }
    }

    // MARK: - Utilities

    /// Whether the user has granted FamilyControls authorization.
    var isAuthorized: Bool {
        authorizationStatus == .approved
    }

    /// Number of apps currently selected for blocking.
    var selectedAppCount: Int {
        selectedApps.applicationTokens.count
    }

    /// Removes all relock timers and active unlocks, then re-applies full shielding.
    /// Useful when the user manually requests an immediate full lockdown.
    func lockdownAll() {
        for (_, timer) in relockTimers {
            timer.invalidate()
        }
        relockTimers.removeAll()
        activeUnlocks.removeAll()
        applyShielding()
        logger.info("Full lockdown engaged — all unlocks revoked.")
    }
}
