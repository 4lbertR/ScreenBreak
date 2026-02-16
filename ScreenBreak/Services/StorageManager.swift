import Foundation
import SwiftData
import SwiftUI
import os

// MARK: - StorageManager

@Observable
@MainActor
final class StorageManager {

    // MARK: - Singleton

    static let shared = StorageManager()

    // MARK: - Model Container

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
        } catch {
            fatalError("Failed to create ModelContainer: \(error.localizedDescription)")
        }
    }

    private var context: ModelContext {
        modelContainer.mainContext
    }

    // MARK: - Unlock Recording

    @discardableResult
    func recordUnlock(appName: String, appBundleID: String, adDuration: Int) -> UnlockSession {
        let session = UnlockSession(
            appBundleID: appBundleID,
            appName: appName,
            unlockedAt: .now,
            expiresAt: Date.now.addingTimeInterval(15 * 60),
            adDurationWatched: adDuration
        )
        context.insert(session)

        let today = DailyStats.fetchOrCreateToday(in: context)
        today.recordUnlock(adSeconds: adDuration)

        let profile = getOrCreateProfile()
        profile.totalLifetimeUnlocks += 1
        profile.totalLifetimeAdSeconds += Double(adDuration)

        saveContext()
        return session
    }

    // MARK: - Queries

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
            logger.error("Failed to fetch today's unlocks: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func getActiveUnlocks() -> [UnlockSession] {
        let now = Date.now
        let predicate = #Predicate<UnlockSession> { session in
            session.expiresAt > now
        }
        let descriptor = FetchDescriptor<UnlockSession>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.expiresAt, order: .forward)]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch active unlocks: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

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
            logger.error("Failed to fetch recent unlocks: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Daily Stats

    func updateDailyStats() {
        let today = DailyStats.fetchOrCreateToday(in: context)
        today.appsBlocked = ScreenTimeManager.shared.selectedAppCount
        saveContext()
    }

    func getWeeklyStats() -> [DailyStats] {
        return DailyStats.history(days: 7, in: context)
    }

    func getStats(forLastDays days: Int) -> [DailyStats] {
        return DailyStats.history(days: days, in: context)
    }

    // MARK: - User Profile

    func getOrCreateProfile() -> UserProfile {
        var descriptor = FetchDescriptor<UserProfile>()
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let profile = UserProfile()
        context.insert(profile)
        saveContext()
        return profile
    }

    // MARK: - Streak Management

    func updateStreak() {
        let profile = getOrCreateProfile()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)

        if let lastEval = profile.lastStreakDate, calendar.isDate(lastEval, inSameDayAs: todayStart) {
            return
        }

        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart) else { return }
        let yesterdayStats = DailyStats.fetchOrCreate(for: yesterday, in: context)

        if yesterdayStats.unlockCount <= profile.dailyUnlockGoal {
            profile.currentStreak += 1
            if profile.currentStreak > profile.longestStreak {
                profile.longestStreak = profile.currentStreak
            }
        } else {
            profile.currentStreak = 0
        }

        profile.lastStreakDate = todayStart
        saveContext()
    }

    // MARK: - Blocked App Info Helpers

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
            logger.error("Failed to fetch blocked apps: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func addBlockedApp(_ app: BlockedAppInfo) {
        context.insert(app)
        saveContext()
    }

    func removeBlockedApp(_ app: BlockedAppInfo) {
        context.delete(app)
        saveContext()
    }

    // MARK: - Data Management

    func deleteAllUnlockSessions() {
        do {
            try context.delete(model: UnlockSession.self)
            saveContext()
        } catch {
            logger.error("Failed to delete UnlockSessions: \(error.localizedDescription, privacy: .public)")
        }
    }

    func resetAllData() {
        do {
            try context.delete(model: UnlockSession.self)
            try context.delete(model: BlockedAppInfo.self)
            try context.delete(model: DailyStats.self)
            try context.delete(model: UserProfile.self)
            saveContext()
        } catch {
            logger.error("Failed to reset data: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private Helpers

    private func saveContext() {
        do {
            try context.save()
        } catch {
            logger.error("Context save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
