import Foundation

/// Central repository for every magic number, string, and configuration value
/// used across the ScreenBreak app.
enum AppConstants {

    // MARK: - Ad Durations (seconds)

    /// Escalating ad durations tied to how many unlocks a user has consumed
    /// in the current rolling one-hour window.
    enum AdDurations {
        /// First unlock in the hour -- 1 minute.
        static let firstUnlock: Int = 60
        /// Second unlock in the hour -- 3 minutes.
        static let secondUnlock: Int = 180
        /// Third (or subsequent) unlock in the hour -- 5 minutes.
        static let thirdPlusUnlock: Int = 300
    }

    // MARK: - Unlock Duration

    /// How long the user keeps access after watching an ad.
    enum UnlockDuration {
        /// 15 minutes of access, expressed in seconds.
        static let accessTime: Int = 900
    }

    // MARK: - AdMob

    /// Google AdMob unit IDs.  These are Google's publicly documented **test**
    /// IDs -- safe to ship in debug builds but must be swapped for real IDs
    /// before production release.
    enum AdMob {
        /// Test banner ad unit ID (Google-provided).
        static let testBannerID        = "ca-app-pub-3940256099942544/2934735716"
        /// Test interstitial ad unit ID (Google-provided).
        static let testInterstitialID  = "ca-app-pub-3940256099942544/4411468910"
        /// Test rewarded-video ad unit ID (Google-provided).
        static let testRewardedID      = "ca-app-pub-3940256099942544/1712485313"

        #if DEBUG
        static let bannerID        = testBannerID
        static let interstitialID  = testInterstitialID
        static let rewardedID      = testRewardedID
        #else
        // TODO: Replace with production ad unit IDs before App Store submission.
        static let bannerID        = testBannerID
        static let interstitialID  = testInterstitialID
        static let rewardedID      = testRewardedID
        #endif
    }

    // MARK: - API

    /// Back-end API configuration.
    enum API {
        static let baseURL = "http://localhost:3000/api"

        /// Timeout for standard network requests (seconds).
        static let requestTimeout: TimeInterval = 30

        /// Timeout for long-running uploads (seconds).
        static let uploadTimeout: TimeInterval = 120
    }

    // MARK: - Strings

    enum Strings {
        static let appName = "ScreenBreak"

        static let tagline = "Break free from your screen."

        static let onboardingTitle = "Take back your time"

        static let onboardingSubtitle =
            "ScreenBreak helps you build healthier screen habits by making you earn your distractions."

        /// A pool of motivational quotes rotated on the dashboard.
        static let motivationalQuotes: [String] = [
            "The secret of getting ahead is getting started. -- Mark Twain",
            "Almost everything will work again if you unplug it for a few minutes, including you. -- Anne Lamott",
            "Your time is limited -- don't waste it living someone else's life. -- Steve Jobs",
            "The best time to plant a tree was 20 years ago. The second best time is now. -- Chinese Proverb",
            "It is not that we have a short time to live, but that we waste a good deal of it. -- Seneca",
            "Disconnect to reconnect.",
            "You don't need more screen time. You need more you time.",
            "Small disciplines repeated with consistency every day lead to great achievements gained slowly over time. -- John C. Maxwell",
            "Be where your feet are.",
            "The phone is a tool, not a lifeline. Put it down and live.",
            "What you do every day matters more than what you do once in a while. -- Gretchen Rubin",
            "Freedom is not the absence of commitment, but the ability to choose. -- Paulo Coelho",
            "Do not dwell in the past, do not dream of the future, concentrate the mind on the present moment. -- Buddha",
            "Less phone, more life.",
            "Every minute you spend on your phone is a minute you don't spend on your dreams."
        ]
    }

    // MARK: - Notification Identifiers

    /// Identifiers used for local notifications and notification categories.
    enum Notifications {
        /// Fired when a temporary unlock is about to expire (2 min warning).
        static let unlockExpiringSoon     = "com.screenbreak.notification.unlockExpiringSoon"

        /// Fired when a temporary unlock has fully expired.
        static let unlockExpired          = "com.screenbreak.notification.unlockExpired"

        /// Daily summary notification (evening recap).
        static let dailySummary           = "com.screenbreak.notification.dailySummary"

        /// Streak milestone (e.g. 7-day, 30-day).
        static let streakMilestone        = "com.screenbreak.notification.streakMilestone"

        /// Motivational nudge sent at a user-configured time.
        static let motivationalNudge      = "com.screenbreak.notification.motivationalNudge"

        /// Reminder that the user hasn't opened the app today.
        static let inactivityReminder     = "com.screenbreak.notification.inactivityReminder"

        /// Notification category for actionable unlock alerts.
        static let unlockCategory         = "com.screenbreak.category.unlock"

        /// Notification action: extend the current session (watch another ad).
        static let actionExtendSession    = "com.screenbreak.action.extendSession"

        /// Notification action: dismiss and re-lock immediately.
        static let actionLockNow          = "com.screenbreak.action.lockNow"
    }

    // MARK: - UserDefaults Keys

    /// Keys written to `UserDefaults` / `@AppStorage`.
    enum Defaults {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let selectedTheme          = "selectedTheme"
        static let notificationsEnabled   = "notificationsEnabled"
        static let lastReviewPromptDate   = "lastReviewPromptDate"
    }

    // MARK: - Keychain / App Group

    enum AppGroup {
        /// Shared App Group identifier (used by the main app + all Screen Time extensions).
        /// Must match the value in every target's entitlements file and `ScreenTimeManager.suiteName`.
        static let identifier = "group.albertreinman.app"
    }
}
