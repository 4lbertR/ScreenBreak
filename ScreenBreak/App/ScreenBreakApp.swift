import SwiftUI
import SwiftData
import FamilyControls

@main
struct ScreenBreakApp: App {
    @State private var screenTimeManager = ScreenTimeManager.shared
    @State private var storageManager = StorageManager.shared
    @State private var adManager = AdManager.shared
    @State private var notificationManager = NotificationManager.shared

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    // Deep-link state: when the shield extension triggers "screenbreak://unlock?app=X"
    @State private var pendingUnlockAppName: String?
    @State private var showAdSheet = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                }
            }
            .preferredColorScheme(.dark)
            .modelContainer(storageManager.modelContainer)
            .sheet(isPresented: $showAdSheet) {
                if let appName = pendingUnlockAppName {
                    let duration = adManager.getRequiredAdDuration(forApp: appName)
                    let attempt = adManager.getUnlockCount(forApp: appName) + 1
                    AdWatchView(
                        appName: appName,
                        appToken: nil,
                        requiredDuration: duration,
                        unlockAttempt: attempt
                    )
                    .interactiveDismissDisabled(true)
                }
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .onAppear {
                Task {
                    await notificationManager.requestPermission()
                }
                adManager.configure()
                storageManager.updateStreak()
                storageManager.updateDailyStats()
                checkPendingUnlock()
            }
        }
    }

    // MARK: - Deep Link Handling

    /// Handles `screenbreak://unlock?app=AppName` URLs from the ShieldActionExtension.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "screenbreak",
              url.host == "unlock" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let appName = components?.queryItems?.first(where: { $0.name == "app" })?.value
            ?? components?.queryItems?.first(where: { $0.name == "domain" })?.value
            ?? "App"

        pendingUnlockAppName = appName
        showAdSheet = true
    }

    /// Checks shared UserDefaults for a pending unlock (fallback from extension).
    private func checkPendingUnlock() {
        guard let defaults = UserDefaults(suiteName: AppConstants.AppGroup.identifier) else { return }
        if let appName = defaults.string(forKey: "screenbreak.pendingUnlockAppName") {
            pendingUnlockAppName = appName
            showAdSheet = true
            // Clear after reading
            defaults.removeObject(forKey: "screenbreak.pendingUnlockAppName")
            defaults.removeObject(forKey: "screenbreak.pendingUnlockTokenData")
            defaults.synchronize()
        }
    }
}
