import Foundation
import SwiftData

/// Tracks each unlock event when a user watches an ad to temporarily access a blocked app.
@Model
final class UnlockSession {

    // MARK: - Stored Properties

    @Attribute(.unique)
    var id: UUID

    /// Bundle identifier of the app that was unlocked (e.g. "com.instagram.ios").
    var appBundleID: String

    /// Human-readable name shown in the UI.
    var appName: String

    /// Timestamp when the user completed the ad and access was granted.
    var unlockedAt: Date

    /// Timestamp when the temporary access window closes.
    var expiresAt: Date

    /// How many seconds of ad the user actually watched to earn this unlock.
    var adDurationWatched: Int

    // MARK: - Computed Properties

    /// `true` while the current time is before the expiration date.
    var isActive: Bool {
        Date.now < expiresAt
    }

    /// Remaining seconds of access, clamped to zero.
    var remainingSeconds: TimeInterval {
        max(expiresAt.timeIntervalSince(.now), 0)
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        appBundleID: String,
        appName: String,
        unlockedAt: Date = .now,
        expiresAt: Date,
        adDurationWatched: Int
    ) {
        self.id = id
        self.appBundleID = appBundleID
        self.appName = appName
        self.unlockedAt = unlockedAt
        self.expiresAt = expiresAt
        self.adDurationWatched = adDurationWatched
    }

    // MARK: - Convenience Factory

    /// Creates a new session using the escalating-ad rules, calculating `expiresAt`
    /// automatically from the current time + the standard access window.
    static func create(
        appBundleID: String,
        appName: String,
        adDurationWatched: Int
    ) -> UnlockSession {
        let now = Date.now
        let expiry = now.addingTimeInterval(
            TimeInterval(AppConstants.UnlockDuration.accessTime)
        )
        return UnlockSession(
            appBundleID: appBundleID,
            appName: appName,
            unlockedAt: now,
            expiresAt: expiry,
            adDurationWatched: adDurationWatched
        )
    }

    // MARK: - Ad Duration Calculation

    /// Returns the number of seconds of ad a user must watch before unlocking,
    /// based on how many times they have already unlocked **any** app in the
    /// rolling one-hour window.
    ///
    /// | Unlocks in last hour | Required ad duration |
    /// |----------------------|----------------------|
    /// | 0 (first)            | 60 s  (1 min)        |
    /// | 1 (second)           | 180 s (3 min)        |
    /// | 2+ (third or more)   | 300 s (5 min)        |
    ///
    /// - Parameter recentSessions: All `UnlockSession` objects whose `unlockedAt`
    ///   falls within the last 60 minutes. The caller is responsible for passing
    ///   a correctly-filtered collection (use the predicate helper below).
    /// - Returns: Required ad watch time in seconds.
    static func requiredAdDuration(givenRecentUnlocks count: Int) -> Int {
        switch count {
        case 0:
            return AppConstants.AdDurations.firstUnlock
        case 1:
            return AppConstants.AdDurations.secondUnlock
        default:
            return AppConstants.AdDurations.thirdPlusUnlock
        }
    }

    /// A predicate that matches sessions whose `unlockedAt` is within the last hour.
    /// Useful for fetching recent sessions from the model context.
    static func recentSessionPredicate(
        since referenceDate: Date = .now
    ) -> Predicate<UnlockSession> {
        let oneHourAgo = referenceDate.addingTimeInterval(-3600)
        return #Predicate<UnlockSession> { session in
            session.unlockedAt >= oneHourAgo
        }
    }

    /// Convenience that takes an array of **all** sessions and filters + counts
    /// in-memory, then returns the required ad duration.
    static func requiredAdDuration(
        basedOn allSessions: [UnlockSession],
        referenceDate: Date = .now
    ) -> Int {
        let oneHourAgo = referenceDate.addingTimeInterval(-3600)
        let recentCount = allSessions.filter { $0.unlockedAt >= oneHourAgo }.count
        return requiredAdDuration(givenRecentUnlocks: recentCount)
    }
}
