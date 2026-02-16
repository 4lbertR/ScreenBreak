import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
class DashboardViewModel {

    // MARK: - Public State

    var todayUnlockCount: Int = 0
    var todayAdTimeWatched: TimeInterval = 0
    var todayTimeSaved: TimeInterval = 0
    var currentStreak: Int = 0
    var activeUnlocks: [ActiveUnlock] = []
    var motivationalQuote: String = ""
    var weeklyData: [DayData] = []
    var dailyGoalProgress: Double = 0.0

    // MARK: - Private

    private var refreshTimer: Timer?

    // MARK: - Nested Types

    struct ActiveUnlock: Identifiable {
        let id: UUID
        let appName: String
        var remainingSeconds: Int
        let expiresAt: Date
    }

    struct DayData: Identifiable {
        let id = UUID()
        let dayName: String   // "Mon", "Tue", etc.
        let unlockCount: Int
        let timeSaved: TimeInterval
    }

    // MARK: - Data Loading

    /// Main entry point: fetches all dashboard data from SwiftData and populates
    /// every published property in one pass.
    func loadData(modelContext: ModelContext) {
        loadTodayStats(modelContext: modelContext)
        refreshActiveUnlocks(modelContext: modelContext)
        loadWeeklyData(modelContext: modelContext)
        loadProfile(modelContext: modelContext)
        pickRandomQuote()
        calculateTimeSaved(modelContext: modelContext)
    }

    // MARK: - Today Stats

    private func loadTodayStats(modelContext: ModelContext) {
        let todayStats = DailyStats.fetchOrCreateToday(in: modelContext)
        todayUnlockCount = todayStats.unlockCount
        todayAdTimeWatched = todayStats.totalAdTimeWatched
    }

    // MARK: - Profile & Streak

    private func loadProfile(modelContext: ModelContext) {
        let profile = UserProfile.fetchOrCreate(in: modelContext)
        currentStreak = profile.streakDays

        // Daily goal progress: ratio of blocked time to the goal.
        // Goal is in minutes; blocked time is in seconds.
        let todayStats = DailyStats.fetchOrCreateToday(in: modelContext)
        let goalSeconds = TimeInterval(profile.dailyGoalMinutes * 60)
        if goalSeconds > 0 {
            dailyGoalProgress = min(todayStats.totalScreenTimeBlocked / goalSeconds, 1.0)
        } else {
            dailyGoalProgress = 0.0
        }
    }

    // MARK: - Active Unlocks

    /// Re-fetches all non-expired unlock sessions and maps them to `ActiveUnlock`
    /// view models with their remaining countdown.
    func refreshActiveUnlocks(modelContext: ModelContext) {
        let now = Date.now
        let predicate = #Predicate<UnlockSession> { session in
            session.expiresAt > now
        }
        var descriptor = FetchDescriptor<UnlockSession>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.expiresAt, order: .forward)]
        )
        descriptor.fetchLimit = 50

        let sessions = (try? modelContext.fetch(descriptor)) ?? []

        activeUnlocks = sessions.map { session in
            let remaining = max(Int(session.expiresAt.timeIntervalSince(now)), 0)
            return ActiveUnlock(
                id: session.id,
                appName: session.appName,
                remainingSeconds: remaining,
                expiresAt: session.expiresAt
            )
        }
    }

    // MARK: - Weekly Data

    /// Loads the last 7 days of `DailyStats` for the weekly chart, ordered from
    /// oldest to newest (left-to-right on a chart).
    func loadWeeklyData(modelContext: ModelContext) {
        let history = DailyStats.history(days: 7, in: modelContext)
        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"   // "Mon", "Tue", ...

        // `history` is ordered most-recent-first; reverse so chart reads L-to-R.
        weeklyData = history.reversed().map { stats in
            DayData(
                dayName: dayFormatter.string(from: stats.date),
                unlockCount: stats.unlockCount,
                timeSaved: stats.totalScreenTimeBlocked
            )
        }
    }

    // MARK: - Motivational Quote

    /// Picks a random motivational quote from the constants pool.
    func pickRandomQuote() {
        motivationalQuote = AppConstants.Strings.motivationalQuotes.randomElement()
            ?? "Break free from your screen."
    }

    // MARK: - Time Saved

    /// Estimates time saved today.
    ///
    /// Heuristic: for every hour during which the user had apps blocked but did
    /// **not** unlock them, we assume 30 minutes of potential screen time was
    /// prevented. We also credit the difference between each unlock's access
    /// window (15 min) and the average session length that would have occurred
    /// without intervention (assumed 30 min).
    func calculateTimeSaved(modelContext: ModelContext) {
        let todayStats = DailyStats.fetchOrCreateToday(in: modelContext)

        // Base: blocked screen time already recorded by the system.
        var saved = todayStats.totalScreenTimeBlocked

        // If there are blocked apps but few unlocks, credit additional estimated savings.
        // Assume each hour with shields active but no unlock = 30 min saved.
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        let hoursSinceStartOfDay = Date.now.timeIntervalSince(startOfToday) / 3600.0

        // Count hours that had no unlock.
        let unblockedHours = Double(todayStats.unlockCount) * 0.25  // each unlock grants 15 min = 0.25 h
        let blockedHours = max(hoursSinceStartOfDay - unblockedHours, 0)
        let estimatedSavedFromBlocking = blockedHours * 30 * 60  // 30 min per blocked hour in seconds

        // Only add the estimate if we have blocked apps configured.
        let screenTimeManager = ScreenTimeManager.shared
        if screenTimeManager.selectedAppCount > 0 {
            saved += estimatedSavedFromBlocking
        }

        todayTimeSaved = saved
    }

    // MARK: - Refresh Timer

    /// Starts a repeating 1-second timer that decrements the countdown on every
    /// active unlock and removes expired ones.
    func startRefreshTimer() {
        stopRefreshTimer()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickActiveUnlocks()
            }
        }
        if let timer = refreshTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// Invalidates the refresh timer.
    func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Timer Tick

    private func tickActiveUnlocks() {
        let now = Date.now
        activeUnlocks = activeUnlocks.compactMap { unlock in
            let remaining = max(Int(unlock.expiresAt.timeIntervalSince(now)), 0)
            guard remaining > 0 else { return nil }
            var updated = unlock
            updated.remainingSeconds = remaining
            return updated
        }
    }
}
