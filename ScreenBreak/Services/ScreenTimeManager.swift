import FamilyControls
import ManagedSettings
import DeviceActivity
import SwiftData
import Foundation
import os

// MARK: - ScreenTimeManager

@Observable
@MainActor
final class ScreenTimeManager {

    // MARK: - Singleton

    static let shared = ScreenTimeManager()

    // MARK: - Published State

    var authorizationStatus: AuthorizationStatus = .notDetermined
    var selectedApps: FamilyActivitySelection = FamilyActivitySelection()
    var isMonitoring: Bool = false
    var activeUnlocks: Set<ApplicationToken> = []

    // MARK: - Private

    private let store = ManagedSettingsStore()
    private let center = AuthorizationCenter.shared
    private let deviceActivityCenter = DeviceActivityCenter()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ScreenBreak",
                                category: "ScreenTimeManager")

    private var relockTimers: [Int: Timer] = [:]

    private static let selectionKey = "screenbreak.familyActivitySelection"
    private static let suiteName = "group.albertreinman.app"

    // MARK: - Init

    private init() {
        loadSelection()
        authorizationStatus = center.authorizationStatus
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        do {
            try await center.requestAuthorization(for: .individual)
            authorizationStatus = center.authorizationStatus
        } catch {
            authorizationStatus = center.authorizationStatus
            logger.error("FamilyControls authorization failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    // MARK: - Shielding

    func applyShielding() {
        let tokensToShield = selectedApps.applicationTokens.subtracting(activeUnlocks)
        guard !tokensToShield.isEmpty else {
            store.shield.applications = nil
            return
        }
        store.shield.applications = tokensToShield
        store.shield.applicationCategories = selectedApps.categoryTokens.isEmpty
            ? nil
            : .specific(selectedApps.categoryTokens)
    }

    func removeShielding() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
    }

    func removeShieldingForApp(token: ApplicationToken) {
        activeUnlocks.insert(token)
        applyShielding()
    }

    func reapplyShieldingForApp(token: ApplicationToken) {
        activeUnlocks.remove(token)
        applyShielding()
    }

    // MARK: - Temporary Unlock

    func temporarilyUnlockApp(token: ApplicationToken, duration: TimeInterval) {
        let key = token.hashValue
        relockTimers[key]?.invalidate()

        removeShieldingForApp(token: token)

        let timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reapplyShieldingForApp(token: token)
                self.relockTimers.removeValue(forKey: key)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        relockTimers[key] = timer
    }

    func cancelRelockTimer(for token: ApplicationToken) {
        let key = token.hashValue
        relockTimers[key]?.invalidate()
        relockTimers.removeValue(forKey: key)
    }

    // MARK: - Device Activity Monitoring

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
        } catch {
            isMonitoring = false
            logger.error("Failed to start monitoring: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopMonitoring() {
        deviceActivityCenter.stopMonitoring()
        isMonitoring = false
    }

    // MARK: - Persistence

    func saveSelection() {
        do {
            let data = try JSONEncoder().encode(selectedApps)
            let defaults = UserDefaults(suiteName: Self.suiteName) ?? .standard
            defaults.set(data, forKey: Self.selectionKey)
        } catch {
            logger.error("Failed to save FamilyActivitySelection: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadSelection() {
        let defaults = UserDefaults(suiteName: Self.suiteName) ?? .standard
        guard let data = defaults.data(forKey: Self.selectionKey) else {
            return
        }
        do {
            selectedApps = try JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        } catch {
            logger.error("Failed to decode saved FamilyActivitySelection: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Utilities

    var isAuthorized: Bool {
        authorizationStatus == .approved
    }

    var selectedAppCount: Int {
        selectedApps.applicationTokens.count
    }

    func lockdownAll() {
        for (_, timer) in relockTimers {
            timer.invalidate()
        }
        relockTimers.removeAll()
        activeUnlocks.removeAll()
        applyShielding()
    }
}
