import Foundation
import SwiftData

/// Aggregated statistics for a single calendar day.
///
/// One row is created per day the app is active.  Views and background tasks
/// should call `fetchOrCreate(for:in:)` to ensure exactly one row exists for
/// any given date.
@Model
final class DailyStats {

    // MARK: - Stored Properties

    @Attribute(.unique)
    var id: UUID

    /// The calendar day these stats belong to (always normalised to start-of-day
    /// in the user's current time zone).
    var date: Date

    /// Cumulative seconds of screen time that was blocked (shielded) today.
    var totalScreenTimeBlocked: TimeInterval

    /// How many times the user unlocked an app today.
    var unlockCount: Int

    /// Cumulative seconds of ad video the user watched today.
    var totalAdTimeWatched: TimeInterval

    /// Number of distinct apps that were on the block list at any point today.
    var appsBlocked: Int

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date = Calendar.current.startOfDay(for: .now),
        totalScreenTimeBlocked: TimeInterval = 0,
        unlockCount: Int = 0,
        totalAdTimeWatched: TimeInterval = 0,
        appsBlocked: Int = 0
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.totalScreenTimeBlocked = totalScreenTimeBlocked
        self.unlockCount = unlockCount
        self.totalAdTimeWatched = totalAdTimeWatched
        self.appsBlocked = appsBlocked
    }

    // MARK: - Convenience Mutators

    /// Record that the user completed one unlock after watching `adSeconds` of ads.
    func recordUnlock(adSeconds: Int) {
        unlockCount += 1
        totalAdTimeWatched += TimeInterval(adSeconds)
    }

    /// Add blocked screen time (typically called when an access window expires or
    /// when the user backgrounds an app while the shield is active).
    func addBlockedTime(_ seconds: TimeInterval) {
        totalScreenTimeBlocked += seconds
    }

    // MARK: - Formatted Accessors

    /// e.g. "2 h 15 m"
    var formattedBlockedTime: String {
        totalScreenTimeBlocked.shortFormatted
    }

    /// e.g. "12 m"
    var formattedAdTime: String {
        totalAdTimeWatched.shortFormatted
    }

    // MARK: - Static Helpers

    /// Fetches today's `DailyStats` row from the given context, creating one if
    /// it does not yet exist.
    @MainActor
    static func fetchOrCreateToday(in context: ModelContext) -> DailyStats {
        fetchOrCreate(for: .now, in: context)
    }

    /// Fetches (or creates) the `DailyStats` row for the calendar day containing
    /// `date`.
    @MainActor
    static func fetchOrCreate(for date: Date, in context: ModelContext) -> DailyStats {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = #Predicate<DailyStats> { stats in
            stats.date >= startOfDay && stats.date < startOfNextDay
        }

        var descriptor = FetchDescriptor<DailyStats>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let newStats = DailyStats(date: startOfDay)
        context.insert(newStats)
        return newStats
    }

    /// Returns stats for the last `days` calendar days (most recent first),
    /// creating missing entries with zeroed-out values.
    @MainActor
    static func history(
        days: Int,
        in context: ModelContext
    ) -> [DailyStats] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        return (0..<days).map { offset in
            let targetDate = calendar.date(byAdding: .day, value: -offset, to: today)!
            return fetchOrCreate(for: targetDate, in: context)
        }
    }

    /// Predicate matching stats rows for the current calendar day.
    static var todayPredicate: Predicate<DailyStats> {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: .now)
        let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return #Predicate<DailyStats> { stats in
            stats.date >= startOfDay && stats.date < startOfNextDay
        }
    }
}
