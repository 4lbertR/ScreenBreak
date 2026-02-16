import Foundation
import UserNotifications
import os

// MARK: - NotificationManager

@Observable
@MainActor
final class NotificationManager {

    // MARK: - Singleton

    static let shared = NotificationManager()

    // MARK: - Observable State

    var isPermissionGranted: Bool = false

    // MARK: - Private

    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ScreenBreak",
                                category: "NotificationManager")

    private enum IDPrefix {
        static let expiryWarning  = "screenbreak.expiry-warning."
        static let relock         = "screenbreak.relock."
        static let dailySummary   = "screenbreak.daily-summary"
        static let motivational   = "screenbreak.motivational."
    }

    private init() {
        Task {
            await refreshPermissionStatus()
        }
    }

    // MARK: - Permission

    func requestPermission() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isPermissionGranted = granted
        } catch {
            isPermissionGranted = false
            logger.error("Notification permission request failed")
        }
    }

    func refreshPermissionStatus() async {
        let settings = await center.notificationSettings()
        isPermissionGranted = settings.authorizationStatus == .authorized
    }

    // MARK: - Unlock Expiry Warning

    func scheduleUnlockExpiryWarning(appName: String, expiresAt: Date) {
        let warningDate = expiresAt.addingTimeInterval(-120)
        let interval = warningDate.timeIntervalSince(.now)

        guard interval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Almost time!"
        content.body = "\(appName) will lock again in 2 minutes. Save your work!"
        content.sound = .default
        content.categoryIdentifier = "EXPIRY_WARNING"
        content.threadIdentifier = appName

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let identifier = "\(IDPrefix.expiryWarning)\(appName).\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error {
                self.logger.error("Failed to schedule expiry warning: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Relock Notification

    func scheduleRelock(appName: String, at relockDate: Date) {
        let interval = relockDate.timeIntervalSince(.now)

        guard interval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "App locked"
        content.body = "\(appName) has been locked again. Stay focused — you've got this!"
        content.sound = .default
        content.categoryIdentifier = "RELOCK"
        content.threadIdentifier = appName

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let identifier = "\(IDPrefix.relock)\(appName).\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error {
                self.logger.error("Failed to schedule relock notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Daily Summary

    func scheduleDailySummary(hour: Int, minute: Int) {
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

        center.add(request) { error in
            if let error {
                self.logger.error("Failed to schedule daily summary: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Motivational Reminders

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

        center.add(request) { error in
            if let error {
                self.logger.error("Failed to schedule motivational reminder: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Cancellation

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func cancelNotification(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    func cancelExpiryWarnings(for appName: String) {
        let prefix = "\(IDPrefix.expiryWarning)\(appName)."
        cancelNotificationsWithPrefix(prefix)
    }

    func cancelRelockNotifications(for appName: String) {
        let prefix = "\(IDPrefix.relock)\(appName)."
        cancelNotificationsWithPrefix(prefix)
    }

    func scheduleUnlockNotifications(appName: String, expiresAt: Date) {
        scheduleUnlockExpiryWarning(appName: appName, expiresAt: expiresAt)
        scheduleRelock(appName: appName, at: expiresAt)
    }

    // MARK: - Private Helpers

    private func cancelNotificationsWithPrefix(_ prefix: String) {
        center.getPendingNotificationRequests { [weak self] requests in
            let idsToCancel = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }

            guard !idsToCancel.isEmpty else { return }

            Task { @MainActor [weak self] in
                self?.center.removePendingNotificationRequests(withIdentifiers: idsToCancel)
            }
        }
    }
}
