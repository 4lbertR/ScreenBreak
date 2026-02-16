import Foundation
import SwiftData

@Observable
@MainActor
class StatsViewModel {

    // MARK: - Time Period

    enum TimePeriod: String, CaseIterable {
        case today   = "Today"
        case week    = "This Week"
        case month   = "This Month"
        case allTime = "All Time"
    }

    // MARK: - Public State

    var selectedPeriod: TimePeriod = .today
    var totalTimeSaved: TimeInterval = 0
    var totalAdTimeWatched: TimeInterval = 0
    var totalUnlocks: Int = 0
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var dailyChartData: [ChartDataPoint] = []
    var mostBlockedApps: [AppUnlockCount] = []

    // MARK: - Nested Types

    struct ChartDataPoint: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let date: Date
    }

    struct AppUnlockCount: Identifiable {
        let id = UUID()
        let appName: String
        let unlockCount: Int
    }

    // MARK: - Data Loading

    /// Top-level loader: aggregates all stats for the currently selected period.
    func loadStats(modelContext: ModelContext) {
        let (start, end) = getDateRange()

        // Fetch DailyStats rows within the selected range.
        let dailyRows = fetchDailyStats(from: start, to: end, in: modelContext)

        totalUnlocks = dailyRows.reduce(0) { $0 + $1.unlockCount }
        totalAdTimeWatched = dailyRows.reduce(0) { $0 + $1.totalAdTimeWatched }
        totalTimeSaved = dailyRows.reduce(0) { $0 + $1.totalScreenTimeBlocked }

        // Streak info lives on the UserProfile singleton.
        let profile = UserProfile.fetchOrCreate(in: modelContext)
        currentStreak = profile.streakDays
        longestStreak = profile.longestStreak

        // Load sub-sections.
        loadDailyChart(modelContext: modelContext)
        loadMostBlocked(modelContext: modelContext)
    }

    // MARK: - Chart Data

    /// Populates `dailyChartData` with one point per day in the selected range.
    /// For "Today" we create a single entry; for longer ranges we create one per
    /// calendar day.
    func loadDailyChart(modelContext: ModelContext) {
        let (start, end) = getDateRange()
        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "MMM d"  // "Feb 16"

        var points: [ChartDataPoint] = []
        var cursor = calendar.startOfDay(for: start)

        while cursor < end {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor)!
            let stats = fetchDailyStats(from: cursor, to: nextDay, in: modelContext)
            let unlocks = stats.reduce(0) { $0 + $1.unlockCount }

            points.append(ChartDataPoint(
                label: dayFormatter.string(from: cursor),
                value: Double(unlocks),
                date: cursor
            ))
            cursor = nextDay
        }

        dailyChartData = points
    }

    // MARK: - Most Blocked Apps

    /// Aggregates `UnlockSession` records within the selected date range,
    /// groups them by `appName`, and sorts descending by count.
    func loadMostBlocked(modelContext: ModelContext) {
        let (start, end) = getDateRange()

        let predicate = #Predicate<UnlockSession> { session in
            session.unlockedAt >= start && session.unlockedAt < end
        }
        var descriptor = FetchDescriptor<UnlockSession>(predicate: predicate)
        descriptor.fetchLimit = 500

        let sessions = (try? modelContext.fetch(descriptor)) ?? []

        // Group by app name, count, sort descending.
        var counts: [String: Int] = [:]
        for session in sessions {
            counts[session.appName, default: 0] += 1
        }

        mostBlockedApps = counts
            .map { AppUnlockCount(appName: $0.key, unlockCount: $0.value) }
            .sorted { $0.unlockCount > $1.unlockCount }
    }

    // MARK: - Date Range

    /// Returns the `(start, end)` date pair for the currently selected period.
    /// `start` is inclusive, `end` is exclusive.
    func getDateRange() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date.now
        let endOfToday = calendar.date(byAdding: .day, value: 1,
                                       to: calendar.startOfDay(for: now))!

        switch selectedPeriod {
        case .today:
            return (calendar.startOfDay(for: now), endOfToday)

        case .week:
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -6,
                                             to: calendar.startOfDay(for: now))!
            return (sevenDaysAgo, endOfToday)

        case .month:
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -29,
                                              to: calendar.startOfDay(for: now))!
            return (thirtyDaysAgo, endOfToday)

        case .allTime:
            // Use a far-past date so we capture everything.
            let distantPast = calendar.date(byAdding: .year, value: -10, to: now)!
            return (distantPast, endOfToday)
        }
    }

    // MARK: - Private Helpers

    /// Fetches `DailyStats` rows whose `date` falls within `[from, to)`.
    private func fetchDailyStats(
        from start: Date,
        to end: Date,
        in modelContext: ModelContext
    ) -> [DailyStats] {
        let predicate = #Predicate<DailyStats> { stats in
            stats.date >= start && stats.date < end
        }
        var descriptor = FetchDescriptor<DailyStats>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        descriptor.fetchLimit = 366  // generous upper bound

        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
