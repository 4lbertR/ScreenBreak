import Foundation
import SwiftData
import SwiftUI
import os

// MARK: - StorageManager

/// Provides a centralised interface for all SwiftData persistence in the ScreenBreak app.
///
/// Owns the `ModelContainer`, exposes convenience methods for recording unlocks,
/// querying statistics, and maintaining streak logic. All context access is funneled
/// through `@MainActor` to satisfy SwiftData's main-actor requirement.
@Observable
@MainActor
final class StorageManager {

    // MARK: - Singleton

    static let shared = StorageManager()

    // MARK: - Model Container

    /// The shared SwiftData model container for all ScreenBreak models.
    let modelContainer: ModelContainer

    // MARK: - Private

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ScreenBreak",
                                category: "StorageManager")

    // MARK: - Init

    private init() {
        do {
            let schema = Schema([
                UnlockSession.self,
                BlockedAppInfo.self,
                DailyStats.self,
                UserProfile.self
            ])
            let configuration = ModelConfiguration(
                "ScreenBreak",
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            logger.info("ModelContainer initialised successfully.")
        } catch {
            // SwiftData container creation is a fatal requirement — the app cannot function without it.
            fatalError("Failed to create ModelContainer: \(error.localizedDescription)")
        }
    }

    /// Direct access to the main-actor-bound model context.
    private var context: ModelContext {
        modelContainer.mainContext
    }

    // MARK: - Unlock Recording

    /// Creates and persists a new `UnlockSession`, updates the daily stats, and increments
    /// the user's lifetime counters.
    ///
    /// - Parameters:
    ///   - appName: The human-readable name of the app that was unlocked.
    ///   - appBundleID: The bundle identifier (or token hash) of the unlocked app.
    ///   - adDuration: How many seconds of ad the user watched.
    /// - Returns: The newly created `UnlockSession`.
    @discardableResult
    func recordUnlock(appName: String, appBundleID: String, adDuration: Int) -> UnlockSession {
        // 1. Create the session.
        let session = UnlockSession(
            appBundleID: appBundleID,
            appName: appName,
            unlockedAt: .now,
            expiresAt: Date.now.addingTimeInterval(15 * 60),  // 15-minute access window
            adDurationWatched: adDuration
        )
        context.insert(session)

        // 2. Update today's aggregated stats.
        let today = DailyStats.fetchOrCreateToday(in: context)
        today.recordUnlock(adSeconds: adDuration)

        // 3. Update user profile lifetime counters.
        let profile = getOrCreateProfile()
        profile.totalLifetimeUnlocks += 1
        profile.totalLifetimeAdSeconds += Double(adDuration)

        // 4. Persist.
        saveContext()

        logger.info("Unlock recorded: \(appName) (\(appBundleID)), ad: \(adDuration)s.")
        return session
    }

    // MARK: - Queries

    /// Fetches all `UnlockSession` rows whose `unlockedAt` falls on today's calendar date.
    func getUnlocksToday() -> [UnlockSession] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: .now)
        let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = #Predicate<UnlockSession> { session in
            session.unlockedAt >= startOfDay && session.unlockedAt < startOfNextDay
        }
        let descriptor = FetchDescriptor<UnlockSession>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.unlockedAt, order: .reverse)]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch today's unlocks: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetches all `UnlockSession` rows that have not yet expired (i.e. `expiresAt` is in the future).
    func getActiveUnlocks() -> [UnlockSession] {
        let now = Date.now
        let predicate = #Predicate<UnlockSession> { session in
            session.expiresAt > now
        }
        let descriptor = FetchDescriptor<UnlockSession>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.expiresAt, order: .ascending)]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch active unlocks: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetches unlocks from the last hour for a specific app, used for escalation calculation.
    func getRecentUnlocks(forApp appBundleID: String) -> [UnlockSession] {
        let oneHourAgo = Date.now.addingTimeInterval(-3600)
        let predicate = #Predicate<UnlockSession> { session in
            session.appBundleID == appBundleID && session.unlockedAt >= oneHourAgo
        }
        let descriptor = FetchDescriptor<UnlockSession>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.unlockedAt, order: .reverse)]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch recent unlocks for \(appBundleID): \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Daily Stats

    /// Aggregates today's unlock data into the current day's `DailyStats` row.
    ///
    /// Call this periodically (e.g. when the app enters the background) to ensure the
    /// stats row is up to date. The heavy lifting is already done incrementally by
    /// `recordUnlock`, so this method mainly reconciles the `appsBlocked` count.
    func updateDailyStats() {
        let today = DailyStats.fetchOrCreateToday(in: context)
        today.appsBlocked = ScreenTimeManager.shared.selectedAppCount
        saveContext()
        logger.info("Daily stats updated: \(today.unlockCount) unlock(s), \(today.appsBlocked) app(s) blocked.")
    }

    /// Returns `DailyStats` rows for the last 7 calendar days (most recent first),
    /// creating zeroed-out entries for any missing days.
    func getWeeklyStats() -> [DailyStats] {
        return DailyStats.history(days: 7, in: context)
    }

    /// Returns `DailyStats` rows for the last `days` calendar days.
    func getStats(forLastDays days: Int) -> [DailyStats] {
        return DailyStats.history(days: days, in: context)
    }

    // MARK: - User Profile

    /// Returns the singleton `UserProfile`, creating one with defaults if none exists.
    func getOrCreateProfile() -> UserProfile {
        var descriptor = FetchDescriptor<UserProfile>()
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let profile = UserProfile()
        context.insert(profile)
        saveContext()
        logger.info("New UserProfile created.")
        return profile
    }

    // MARK: - Streak Management

    /// Evaluates whether the user met their daily goal yesterday and updates the streak
    /// accordingly.
    ///
    /// **Logic:**
    /// 1. Determine yesterday's `DailyStats`.
    /// 2. If `unlockCount <= dailyUnlockGoal`, increment the streak.
    /// 3. Otherwise, reset the streak to 0.
    /// 4. Update `longestStreak` if the current streak exceeds it.
    /// 5. Save `lastStreakDate` so the evaluation only happens once per day.
    func updateStreak() {
        let profile = getOrCreateProfile()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)

        // Only evaluate once per calendar day.
        if let lastEval = profile.lastStreakDate, calendar.isDate(lastEval, inSameDayAs: todayStart) {
            return
        }

        // Look at yesterday's stats.
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart) else { return }
        let yesterdayStats = DailyStats.fetchOrCreate(for: yesterday, in: context)

        if yesterdayStats.unlockCount <= profile.dailyUnlockGoal {
            profile.currentStreak += 1
            if profile.currentStreak > profile.longestStreak {
                profile.longestStreak = profile.currentStreak
            }
            logger.info("Streak incremented to \(profile.currentStreak). Goal: \(profile.dailyUnlockGoal), unlocks: \(yesterdayStats.unlockCount).")
        } else {
            let previousStreak = profile.currentStreak
            profile.currentStreak = 0
            logger.info("Streak reset (was \(previousStreak)). Goal: \(profile.dailyUnlockGoal), unlocks: \(yesterdayStats.unlockCount).")
        }

        profile.lastStreakDate = todayStart
        saveContext()
    }

    // MARK: - Blocked App Info Helpers

    /// Fetches all `BlockedAppInfo` entries that are currently enabled.
    func getEnabledBlockedApps() -> [BlockedAppInfo] {
        let predicate = #Predicate<BlockedAppInfo> { app in
            app.isEnabled == true
        }
        let descriptor = FetchDescriptor<BlockedAppInfo>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.displayName)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch blocked apps: \(error.localizedDescription)")
            return []
        }
    }

    /// Saves a new `BlockedAppInfo` record.
    func addBlockedApp(_ app: BlockedAppInfo) {
        context.insert(app)
        saveContext()
    }

    /// Removes a `BlockedAppInfo` record.
    func removeBlockedApp(_ app: BlockedAppInfo) {
        context.delete(app)
        saveContext()
    }

    // MARK: - Data Management

    /// Deletes all `UnlockSession` records (e.g. for a privacy / data reset).
    func deleteAllUnlockSessions() {
        do {
            try context.delete(model: UnlockSession.self)
            saveContext()
            logger.info("All UnlockSession records deleted.")
        } catch {
            logger.error("Failed to delete UnlockSessions: \(error.localizedDescription)")
        }
    }

    /// Deletes **all** persisted data across every model type. Use with caution.
    func resetAllData() {
        do {
            try context.delete(model: UnlockSession.self)
            try context.delete(model: BlockedAppInfo.self)
            try context.delete(model: DailyStats.self)
            try context.delete(model: UserProfile.self)
            saveContext()
            logger.info("All data reset successfully.")
        } catch {
            logger.error("Failed to reset data: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    /// Persists any pending changes in the main context.
    private func saveContext() {
        do {
            try context.save()
        } catch {
            logger.error("Context save failed: \(error.localizedDescription)")
        }
    }
}
