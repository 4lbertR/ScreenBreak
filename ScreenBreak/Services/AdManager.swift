import Foundation
import SwiftUI
import os

// MARK: - AdManager

@Observable
@MainActor
final class AdManager {

    // MARK: - Singleton

    static let shared = AdManager()

    // MARK: - Configuration

    var useMockAds: Bool = true

    // MARK: - Observable State

    var isAdLoaded: Bool = false
    var isShowingAd: Bool = false
    var adProgress: Double = 0.0
    var remainingAdTime: Int = 0
    var currentAdDuration: Int = 0
    var currentTierLabel: String = ""

    // MARK: - Unlock History (Escalation Tracking)

    private var unlockHistory: [String: [Date]] = [:]

    // MARK: - Private

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ScreenBreak",
                                category: "AdManager")

    private var countdownTimer: Timer?
    private var playbackCompletion: ((Bool) -> Void)?
    private var elapsedSeconds: Double = 0

    private enum AdUnitID {
        static let rewardedTest = "ca-app-pub-3940256099942544/1712485313"
    }

    private init() {}

    // MARK: - SDK Configuration

    func configure() {
        if useMockAds {
            isAdLoaded = true
        }
    }

    // MARK: - Escalation Logic

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
        return duration
    }

    func recordUnlock(forApp appID: String) {
        var timestamps = unlockHistory[appID] ?? []
        timestamps.append(Date.now)
        unlockHistory[appID] = timestamps
    }

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

    func getUnlockCount(forApp appID: String) -> Int {
        cleanExpiredHistory()
        return unlockHistory[appID]?.count ?? 0
    }

    func resetHistory() {
        unlockHistory.removeAll()
    }

    // MARK: - Ad Loading

    func loadAd() async {
        if useMockAds {
            isAdLoaded = true
            return
        }
        await loadRealAd()
    }

    private func loadRealAd() async {
        isAdLoaded = false
        logger.warning("Real ad loading is not yet implemented — AdMob SDK not linked.")
    }

    // MARK: - Ad Playback

    func startAdPlayback(duration: Int, completion: @escaping (Bool) -> Void) {
        guard !isShowingAd else { return }

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
    }

    func startAdPlayback(duration: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            startAdPlayback(duration: duration) { success in
                continuation.resume(returning: success)
            }
        }
    }

    // MARK: - Mock Ad Countdown

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

        if let timer = countdownTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    // MARK: - Real Ad Presentation

    private func startRealAdPresentation(duration: Int) {
        logger.warning("Real ad presentation not yet implemented — falling back to mock.")
        startMockCountdown(duration: duration)
    }

    // MARK: - Completion

    private func finishAdPlayback(success: Bool) {
        isShowingAd = false
        adProgress = success ? 1.0 : adProgress
        remainingAdTime = 0

        let completion = playbackCompletion
        playbackCompletion = nil

        Task {
            await loadAd()
        }

        completion?(success)
    }

    // MARK: - Formatting Helpers

    static func formattedTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func tierDescription(forUnlockCount count: Int) -> String {
        switch count {
        case 0:  return "1 minute ad"
        case 1:  return "3 minute ad"
        default: return "5 minute ad"
        }
    }
}
