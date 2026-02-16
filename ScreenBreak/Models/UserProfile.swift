import Foundation
import SwiftData

/// Singleton-style user profile that stores preferences, streaks, and lifetime progress.
///
/// The app should maintain exactly one `UserProfile` row. Use
/// `fetchOrCreate(in:)` on first launch (and everywhere else) to guarantee this.
@Model
final class UserProfile {

    // MARK: - Stored Properties

    @Attribute(.unique)
    var id: UUID

    /// Name shown on the dashboard / stats screen.
    var displayName: String

    /// Current consecutive days the user has stayed under their screen-time goal.
    var streakDays: Int

    /// All-time longest streak (in days).
    var longestStreak: Int

    /// Total calendar days since the user installed the app.
    var totalDaysUsing: Int

    /// The user's self-set daily screen-time goal, in minutes.
    var dailyGoalMinutes: Int

    /// The user's daily unlock-count goal. Staying at or below this number counts
    /// as a "good day" and advances the streak.
    var dailyUnlockGoal: Int

    /// Date the profile was first created.
    var joinDate: Date

    /// Whether to show motivational quotes on the dashboard.
    var motivationalQuoteEnabled: Bool

    /// Total number of unlocks since the app was installed.
    var totalLifetimeUnlocks: Int

    /// Total seconds of ad video watched since install.
    var totalLifetimeAdSeconds: Double

    /// Date of the last streak evaluation (start-of-day). Used to detect day rollovers.
    var lastStreakDate: Date?

    /// ISO-8601 auth token received from the backend (optional — app works fully offline).
    var authToken: String?

    /// Remote user ID assigned by the backend (optional).
    var remoteUserID: String?

    // MARK: - Init

    init(
        id: UUID = UUID(),
        displayName: String = "User",
        streakDays: Int = 0,
        longestStreak: Int = 0,
        totalDaysUsing: Int = 0,
        dailyGoalMinutes: Int = 120,
        dailyUnlockGoal: Int = 5,
        joinDate: Date = .now,
        motivationalQuoteEnabled: Bool = true,
        totalLifetimeUnlocks: Int = 0,
        totalLifetimeAdSeconds: Double = 0,
        lastStreakDate: Date? = nil,
        authToken: String? = nil,
        remoteUserID: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.streakDays = streakDays
        self.longestStreak = longestStreak
        self.totalDaysUsing = totalDaysUsing
        self.dailyGoalMinutes = dailyGoalMinutes
        self.dailyUnlockGoal = dailyUnlockGoal
        self.joinDate = joinDate
        self.motivationalQuoteEnabled = motivationalQuoteEnabled
        self.totalLifetimeUnlocks = totalLifetimeUnlocks
        self.totalLifetimeAdSeconds = totalLifetimeAdSeconds
        self.lastStreakDate = lastStreakDate
        self.authToken = authToken
        self.remoteUserID = remoteUserID
    }

    // MARK: - Computed Properties

    /// Alias for `streakDays` for compatibility with StorageManager/ViewModels.
    var currentStreak: Int {
        get { streakDays }
        set { streakDays = newValue }
    }

    /// Number of whole days since the user joined.
    var daysSinceJoin: Int {
        Calendar.current.dateComponents([.day], from: joinDate, to: .now).day ?? 0
    }

    /// A random motivational quote (if enabled), otherwise `nil`.
    var currentQuote: String? {
        guard motivationalQuoteEnabled else { return nil }
        return AppConstants.Strings.motivationalQuotes.randomElement()
    }

    // MARK: - Streak Management

    /// Call once per day after evaluating whether the user met their daily goal.
    ///
    /// - Parameter metGoal: `true` if the user stayed under `dailyGoalMinutes`.
    func updateStreak(metGoal: Bool) {
        if metGoal {
            streakDays += 1
            if streakDays > longestStreak {
                longestStreak = streakDays
            }
        } else {
            streakDays = 0
        }
        totalDaysUsing = daysSinceJoin
    }

    // MARK: - Singleton Fetch

    /// Returns the single `UserProfile`, creating a default one if none exists.
    @MainActor
    static func fetchOrCreate(in context: ModelContext) -> UserProfile {
        var descriptor = FetchDescriptor<UserProfile>()
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let profile = UserProfile()
        context.insert(profile)
        return profile
    }
}
