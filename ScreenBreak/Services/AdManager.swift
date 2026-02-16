import Foundation
import SwiftUI
import os
// import GoogleMobileAds  // Uncomment when the AdMob SDK pod / SPM package is installed.

// MARK: - AdManager

/// Manages ad loading, playback, and the escalating-duration unlock system.
///
/// Supports two operational modes:
/// - **Mock mode** (`useMockAds = true`): A built-in timer simulates ad playback.
///   Ideal for development and Simulator testing where the AdMob SDK is unavailable.
/// - **Real mode** (`useMockAds = false`): Integrates with Google AdMob rewarded ads.
///   Requires the GoogleMobileAds SDK to be linked and properly configured.
///
/// The escalation rules are:
/// | Unlocks in last hour | Required ad duration |
/// |----------------------|----------------------|
/// | 0 (first)            | 60 s  (1 min)        |
/// | 1 (second)           | 180 s (3 min)        |
/// | 2+ (third or more)   | 300 s (5 min)        |
@Observable
@MainActor
final class AdManager {

    // MARK: - Singleton

    static let shared = AdManager()

    // MARK: - Configuration

    /// When `true` the manager uses an internal timer to simulate ad playback instead of
    /// making real AdMob SDK calls. Set to `false` for production builds.
    var useMockAds: Bool = true

    // MARK: - Observable State

    /// Whether a real (or mock) ad is preloaded and ready to present.
    var isAdLoaded: Bool = false

    /// Whether an ad is currently being displayed / counting down.
    var isShowingAd: Bool = false

    /// Progress of the current ad playback, ranging from `0.0` (just started) to `1.0` (complete).
    var adProgress: Double = 0.0

    /// Seconds remaining in the current ad playback.
    var remainingAdTime: Int = 0

    /// The total duration (in seconds) that was requested for the current ad session.
    var currentAdDuration: Int = 0

    /// Human-readable label for the current escalation tier (e.g. "1st unlock — 1 min ad").
    var currentTierLabel: String = ""

    // MARK: - Unlock History (Escalation Tracking)

    /// Maps an app identifier (bundle ID or token hash string) to an ordered array of
    /// timestamps representing each unlock within the rolling window.
    private var unlockHistory: [String: [Date]] = [:]

    // MARK: - Private

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ScreenBreak",
                                category: "AdManager")

    /// The display link / timer used for mock ad countdown.
    private var countdownTimer: Timer?

    /// Completion handler stashed during ad playback.
    private var playbackCompletion: ((Bool) -> Void)?

    /// Elapsed seconds tracked with sub-second precision for the mock timer.
    private var elapsedSeconds: Double = 0

    // TODO: Uncomment when AdMob SDK is linked.
    // private var rewardedAd: GADRewardedAd?

    // MARK: - Ad Unit IDs

    /// Test ad unit IDs from Google. Replace with real IDs for production.
    private enum AdUnitID {
        static let rewardedTest = "ca-app-pub-3940256099942544/1712485313"
        // static let rewardedProduction = "ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX"
    }

    // MARK: - Init

    private init() {}

    // MARK: - SDK Configuration

    /// Initialises the ad subsystem. Call once at app launch (typically in `App.init` or
    /// the root view's `.onAppear`).
    func configure() {
        if useMockAds {
            isAdLoaded = true
            logger.info("AdManager configured in MOCK mode.")
        } else {
            // TODO: Uncomment when AdMob SDK is linked.
            // GADMobileAds.sharedInstance().start { [weak self] status in
            //     self?.logger.info("AdMob SDK started. Adapter statuses: \(status.adapterStatusesByClassName)")
            //     Task { @MainActor in self?.loadRealAd() }
            // }
            logger.info("AdManager configured for real AdMob ads.")
        }
    }

    // MARK: - Escalation Logic

    /// Returns the required ad duration (in seconds) that a user must watch before unlocking
    /// the specified app, based on the number of unlocks in the rolling one-hour window.
    ///
    /// - Parameter appID: A stable identifier for the app (bundle ID or token hash).
    /// - Returns: `60`, `180`, or `300` depending on escalation tier.
    func getRequiredAdDuration(forApp appID: String) -> Int {
        cleanExpiredHistory()
        let count = unlockHistory[appID]?.count ?? 0
        let duration: Int
        switch count {
        case 0:
            duration = 60
            currentTierLabel = "1st unlock — 1 min ad"
        case 1:
            duration = 180
            currentTierLabel = "2nd unlock — 3 min ad"
        default:
            duration = 300
            currentTierLabel = "3rd+ unlock — 5 min ad"
        }
        logger.info("App \(appID): \(count) recent unlock(s) → \(duration)s ad required.")
        return duration
    }

    /// Records that an unlock just occurred for the specified app. This timestamp will be
    /// used for escalation calculation until it expires after one hour.
    ///
    /// - Parameter appID: A stable identifier for the app (bundle ID or token hash).
    func recordUnlock(forApp appID: String) {
        var timestamps = unlockHistory[appID] ?? []
        timestamps.append(Date.now)
        unlockHistory[appID] = timestamps
        logger.info("Unlock recorded for \(appID). History count: \(timestamps.count).")
    }

    /// Removes all unlock history entries that are older than one hour. Called automatically
    /// before each escalation check, but can also be called manually.
    func cleanExpiredHistory() {
        let oneHourAgo = Date.now.addingTimeInterval(-3600)
        for (appID, timestamps) in unlockHistory {
            let filtered = timestamps.filter { $0 > oneHourAgo }
            if filtered.isEmpty {
                unlockHistory.removeValue(forKey: appID)
            } else {
                unlockHistory[appID] = filtered
            }
        }
    }

    /// Returns the number of unlock events within the last hour for the given app.
    ///
    /// - Parameter appID: A stable identifier for the app.
    /// - Returns: Count of recent unlocks (0, 1, 2, …).
    func getUnlockCount(forApp appID: String) -> Int {
        cleanExpiredHistory()
        return unlockHistory[appID]?.count ?? 0
    }

    /// Clears all unlock history for every app. Useful for testing or a "reset" feature.
    func resetHistory() {
        unlockHistory.removeAll()
        logger.info("All unlock history cleared.")
    }

    // MARK: - Ad Loading

    /// Preloads the next ad so it is ready to display instantly when the user requests an unlock.
    func loadAd() async {
        if useMockAds {
            // Mock ads are always "loaded".
            isAdLoaded = true
            return
        }

        await loadRealAd()
    }

    /// Loads a real Google AdMob rewarded ad.
    private func loadRealAd() async {
        // TODO: Uncomment when AdMob SDK is linked.
        // do {
        //     rewardedAd = try await GADRewardedAd.load(
        //         withAdUnitID: AdUnitID.rewardedTest,
        //         request: GADRequest()
        //     )
        //     isAdLoaded = true
        //     logger.info("Rewarded ad loaded successfully.")
        // } catch {
        //     isAdLoaded = false
        //     logger.error("Failed to load rewarded ad: \(error.localizedDescription)")
        // }
        isAdLoaded = false
        logger.warning("Real ad loading is not yet implemented — AdMob SDK not linked.")
    }

    // MARK: - Ad Playback

    /// Begins ad playback for the specified duration. The user **cannot** skip or cancel
    /// the ad; the completion handler fires only when the full duration has elapsed.
    ///
    /// - Parameters:
    ///   - duration: Total ad time in seconds.
    ///   - completion: Called with `true` when the ad completes successfully, or `false`
    ///     if an unrecoverable error occurs (should be extremely rare with mock ads).
    func startAdPlayback(duration: Int, completion: @escaping (Bool) -> Void) {
        guard !isShowingAd else {
            logger.warning("Ad playback requested while already showing an ad — ignoring.")
            return
        }

        currentAdDuration = duration
        remainingAdTime = duration
        adProgress = 0.0
        elapsedSeconds = 0
        isShowingAd = true
        playbackCompletion = completion

        if useMockAds {
            startMockCountdown(duration: duration)
        } else {
            startRealAdPresentation(duration: duration)
        }

        logger.info("Ad playback started: \(duration)s.")
    }

    /// Provides an async/await wrapper around `startAdPlayback(duration:completion:)`.
    ///
    /// - Parameter duration: Total ad time in seconds.
    /// - Returns: `true` if the ad completed successfully.
    func startAdPlayback(duration: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            startAdPlayback(duration: duration) { success in
                continuation.resume(returning: success)
            }
        }
    }

    // MARK: - Mock Ad Countdown

    /// Starts a 1-second repeating timer that drives the mock ad experience.
    private func startMockCountdown(duration: Int) {
        countdownTimer?.invalidate()

        let totalDuration = Double(duration)

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }

                self.elapsedSeconds += 1.0
                self.remainingAdTime = max(duration - Int(self.elapsedSeconds), 0)
                self.adProgress = min(self.elapsedSeconds / totalDuration, 1.0)

                if self.elapsedSeconds >= totalDuration {
                    timer.invalidate()
                    self.countdownTimer = nil
                    self.finishAdPlayback(success: true)
                }
            }
        }

        // Ensure countdown continues during user interaction (e.g. scrolling).
        if let timer = countdownTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    // MARK: - Real Ad Presentation

    /// Presents a real AdMob rewarded ad using the currently-loaded `rewardedAd`.
    private func startRealAdPresentation(duration: Int) {
        // TODO: Uncomment when AdMob SDK is linked.
        //
        // guard let ad = rewardedAd else {
        //     logger.error("No rewarded ad available to present.")
        //     finishAdPlayback(success: false)
        //     return
        // }
        //
        // guard let rootVC = UIApplication.shared.connectedScenes
        //     .compactMap({ $0 as? UIWindowScene })
        //     .flatMap(\.windows)
        //     .first(where: \.isKeyWindow)?
        //     .rootViewController else {
        //     logger.error("Could not find root view controller to present ad.")
        //     finishAdPlayback(success: false)
        //     return
        // }
        //
        // ad.present(fromRootViewController: rootVC) { [weak self] in
        //     // User earned the reward — but we still enforce our own timer.
        //     // The mock countdown overlay runs concurrently with the real ad to
        //     // ensure the full required duration is served.
        // }
        //
        // // Start an overlay countdown that enforces the minimum watch time even if
        // // the real ad is shorter than the required duration.
        // startMockCountdown(duration: duration)

        logger.warning("Real ad presentation not yet implemented — falling back to mock.")
        startMockCountdown(duration: duration)
    }

    // MARK: - Completion

    /// Shared cleanup called when ad playback finishes (mock or real).
    private func finishAdPlayback(success: Bool) {
        isShowingAd = false
        adProgress = success ? 1.0 : adProgress
        remainingAdTime = 0

        let completion = playbackCompletion
        playbackCompletion = nil

        // Preload the next ad in the background.
        Task {
            await loadAd()
        }

        logger.info("Ad playback finished. Success: \(success).")
        completion?(success)
    }

    // MARK: - Formatting Helpers

    /// Returns a human-readable string for the given number of seconds (e.g. "2:45").
    static func formattedTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// A short label describing the escalation tier for the given number of past unlocks.
    static func tierDescription(forUnlockCount count: Int) -> String {
        switch count {
        case 0:  return "1 minute ad"
        case 1:  return "3 minute ad"
        default: return "5 minute ad"
        }
    }
}
