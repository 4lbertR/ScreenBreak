import Foundation
import UserNotifications
import os

// MARK: - NotificationManager

/// Handles all local notification scheduling for the ScreenBreak app.
///
/// Responsibilities include:
/// - Requesting user permission for notifications.
/// - Warning users before an unlocked app re-locks.
/// - Notifying when an app has been re-locked.
/// - Scheduling a recurring daily summary.
/// - Delivering motivational reminders to encourage reduced screen time.
///
/// All scheduling uses `UNUserNotificationCenter` with `UNTimeIntervalNotificationTrigger`
/// or `UNCalendarNotificationTrigger` as appropriate.
@Observable
@MainActor
final class NotificationManager {

    // MARK: - Singleton

    static let shared = NotificationManager()

    // MARK: - Observable State

    /// Whether the user has granted notification permission.
    var isPermissionGranted: Bool = false

    // MARK: - Private

    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ScreenBreak",
                                category: "NotificationManager")

    // MARK: - Notification Identifiers

    /// Structured identifier prefixes so we can cancel specific categories of notifications.
    private enum IDPrefix {
        static let expiryWarning  = "screenbreak.expiry-warning."
        static let relock         = "screenbreak.relock."
        static let dailySummary   = "screenbreak.daily-summary"
        static let motivational   = "screenbreak.motivational."
    }

    // MARK: - Init

    private init() {
        Task {
            await refreshPermissionStatus()
        }
    }

    // MARK: - Permission

    /// Requests authorization to display alerts, sounds, and badges.
    ///
    /// Safe to call multiple times — the system only shows the prompt once and returns
    /// the cached result on subsequent calls.
    func requestPermission() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isPermissionGranted = granted
            if granted {
                logger.info("Notification permission granted.")
            } else {
                logger.info("Notification permission denied by user.")
            }
        } catch {
            isPermissionGranted = false
            logger.error("Notification permission request failed: \(error.localizedDescription)")
        }
    }

    /// Checks current authorization status without prompting the user.
    func refreshPermissionStatus() async {
        let settings = await center.notificationSettings()
        isPermissionGranted = settings.authorizationStatus == .authorized
    }

    // MARK: - Unlock Expiry Warning

    /// Schedules a notification that fires **2 minutes before** an unlocked app re-locks,
    /// giving the user a heads-up to finish what they are doing.
    ///
    /// - Parameters:
    ///   - appName: Display name of the app (e.g. "Instagram").
    ///   - expiresAt: The exact `Date` when the unlock window closes.
    func scheduleUnlockExpiryWarning(appName: String, expiresAt: Date) {
        let warningDate = expiresAt.addingTimeInterval(-120) // 2 minutes before expiry
        let interval = warningDate.timeIntervalSince(.now)

        guard interval > 0 else {
            logger.info("Expiry warning not scheduled — warning time already passed for \(appName).")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Almost time!"
        content.body = "\(appName) will lock again in 2 minutes. Save your work!"
        content.sound = .default
        content.categoryIdentifier = "EXPIRY_WARNING"
        content.threadIdentifier = appName

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let identifier = "\(IDPrefix.expiryWarning)\(appName).\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { [logger] error in
            if let error {
                logger.error("Failed to schedule expiry warning for \(appName): \(error.localizedDescription)")
            } else {
                logger.info("Expiry warning scheduled for \(appName) at \(warningDate).")
            }
        }
    }

    // MARK: - Relock Notification

    /// Schedules a notification that fires when an unlocked app is re-locked.
    ///
    /// - Parameters:
    ///   - appName: Display name of the app.
    ///   - at: The exact `Date` when the app re-locks.
    func scheduleRelock(appName: String, at relockDate: Date) {
        let interval = relockDate.timeIntervalSince(.now)

        guard interval > 0 else {
            logger.info("Relock notification not scheduled — relock time already passed for \(appName).")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "App locked"
        content.body = "\(appName) has been locked again. Stay focused — you've got this!"
        content.sound = .default
        content.categoryIdentifier = "RELOCK"
        content.threadIdentifier = appName

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let identifier = "\(IDPrefix.relock)\(appName).\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { [logger] error in
            if let error {
                logger.error("Failed to schedule relock notification for \(appName): \(error.localizedDescription)")
            } else {
                logger.info("Relock notification scheduled for \(appName) at \(relockDate).")
            }
        }
    }

    // MARK: - Daily Summary

    /// Schedules a daily repeating notification that reminds the user to check their
    /// screen-time summary.
    ///
    /// - Parameters:
    ///   - hour: Hour component (0-23) in the user's local time zone.
    ///   - minute: Minute component (0-59).
    func scheduleDailySummary(hour: Int, minute: Int) {
        // Remove any existing daily summary first to avoid duplicates.
        center.removePendingNotificationRequests(withIdentifiers: [IDPrefix.dailySummary])

        let content = UNMutableNotificationContent()
        content.title = "Daily Screen Time Summary"
        content.body = "Tap to see how you did today. Every day under your goal builds your streak!"
        content.sound = .default
        content.categoryIdentifier = "DAILY_SUMMARY"

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: IDPrefix.dailySummary,
                                            content: content,
                                            trigger: trigger)

        center.add(request) { [logger] error in
            if let error {
                logger.error("Failed to schedule daily summary: \(error.localizedDescription)")
            } else {
                logger.info("Daily summary notification scheduled at \(hour):\(minute).")
            }
        }
    }

    // MARK: - Motivational Reminders

    /// Schedules a motivational reminder at a random time within the next 4-8 hours.
    ///
    /// Each call schedules exactly one notification; the app should re-schedule after
    /// the notification is delivered (typically in the notification delegate).
    func scheduleMotivationalReminder() {
        let quotes: [String] = [
            "Every minute you resist is a minute you invest in yourself.",
            "Your future self will thank you for staying focused today.",
            "Discipline is choosing between what you want now and what you want most.",
            "Small steps every day lead to big changes over time.",
            "You don't need that app right now. You need your peace of mind.",
            "The best time to break a habit is right now.",
            "Screen time down, life time up.",
            "You are stronger than your urge to scroll.",
            "Focus is a superpower. Keep training it.",
            "Real life has better graphics than any screen.",
            "One less unlock today means one step closer to freedom.",
            "Your attention is valuable — spend it wisely.",
            "The scroll can wait. Your goals cannot.",
            "Be present. Be powerful. Be phone-free."
        ]

        let randomQuote = quotes.randomElement() ?? quotes[0]

        // Random delay between 4 and 8 hours.
        let minDelay: TimeInterval = 4 * 3600
        let maxDelay: TimeInterval = 8 * 3600
        let delay = TimeInterval.random(in: minDelay...maxDelay)

        let content = UNMutableNotificationContent()
        content.title = "ScreenBreak"
        content.body = randomQuote
        content.sound = .default
        content.categoryIdentifier = "MOTIVATIONAL"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let identifier = "\(IDPrefix.motivational)\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { [logger] error in
            if let error {
                logger.error("Failed to schedule motivational reminder: \(error.localizedDescription)")
            } else {
                logger.info("Motivational reminder scheduled in \(Int(delay / 60)) minutes.")
            }
        }
    }

    // MARK: - Cancellation

    /// Removes all pending and delivered notifications managed by ScreenBreak.
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        logger.info("All notifications cancelled.")
    }

    /// Cancels a single pending notification by its identifier.
    ///
    /// - Parameter id: The notification request identifier to cancel.
    func cancelNotification(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
        logger.info("Notification cancelled: \(id).")
    }

    /// Cancels all expiry-warning notifications for a specific app.
    ///
    /// - Parameter appName: The display name of the app whose warnings should be cancelled.
    func cancelExpiryWarnings(for appName: String) {
        let prefix = "\(IDPrefix.expiryWarning)\(appName)."
        cancelNotificationsWithPrefix(prefix)
    }

    /// Cancels all relock notifications for a specific app.
    ///
    /// - Parameter appName: The display name of the app.
    func cancelRelockNotifications(for appName: String) {
        let prefix = "\(IDPrefix.relock)\(appName)."
        cancelNotificationsWithPrefix(prefix)
    }

    // MARK: - Convenience: Schedule Both Expiry Warning and Relock

    /// Schedules both the 2-minute expiry warning and the relock notification for an
    /// unlock session. This is the typical call made by the unlock flow.
    ///
    /// - Parameters:
    ///   - appName: The display name of the app.
    ///   - expiresAt: When the unlock window closes.
    func scheduleUnlockNotifications(appName: String, expiresAt: Date) {
        scheduleUnlockExpiryWarning(appName: appName, expiresAt: expiresAt)
        scheduleRelock(appName: appName, at: expiresAt)
    }

    // MARK: - Private Helpers

    /// Cancels all pending notifications whose identifier starts with the given prefix.
    private func cancelNotificationsWithPrefix(_ prefix: String) {
        center.getPendingNotificationRequests { [weak self, logger] requests in
            let idsToCancel = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }

            guard !idsToCancel.isEmpty else { return }

            Task { @MainActor [weak self] in
                self?.center.removePendingNotificationRequests(withIdentifiers: idsToCancel)
                logger.info("Cancelled \(idsToCancel.count) notification(s) with prefix '\(prefix)'.")
            }
        }
    }
}
