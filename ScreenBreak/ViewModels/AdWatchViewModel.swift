import Foundation
import SwiftUI
import Combine

@Observable
@MainActor
class AdWatchViewModel {

    // MARK: - Public State

    /// Display name of the app being unlocked.
    let appName: String

    /// Total seconds the user must watch before the unlock is granted.
    let requiredDuration: Int

    /// Seconds still remaining on the countdown.
    var remainingTime: Int = 0

    /// 0.0 ... 1.0 progress toward completion.
    var progress: Double = 0.0

    /// `true` while the countdown timer is actively running.
    var isPlaying: Bool = false

    /// `true` once the full ad duration has been watched.
    var isCompleted: Bool = false

    /// Which attempt this is within the rolling hour (1st, 2nd, 3rd+).
    let attemptNumber: Int

    /// `true` when the user is allowed to dismiss the ad screen.
    var canDismiss: Bool = false

    /// Human-readable status line shown beneath the progress indicator.
    var statusText: String = "Preparing ad..."

    // MARK: - Private

    /// The repeating 1-second timer driving the countdown.
    private var timer: Timer?

    /// The wall-clock time when `startAd()` was called, used to calculate
    /// elapsed time independently of timer drift.
    private var startTime: Date?

    // MARK: - Init

    /// - Parameters:
    ///   - appName: Display name of the app being unlocked.
    ///   - requiredDuration: Total seconds of ad the user must watch.
    ///   - attemptNumber: 1-based attempt index within the current hour.
    init(appName: String, requiredDuration: Int, attemptNumber: Int) {
        self.appName = appName
        self.requiredDuration = requiredDuration
        self.attemptNumber = attemptNumber
        self.remainingTime = requiredDuration
    }

    // MARK: - Ad Lifecycle

    /// Begins the unskippable countdown timer. The timer fires every second,
    /// decrementing `remainingTime` and advancing `progress`. When the countdown
    /// reaches zero `onAdComplete()` is called automatically.
    func startAd() {
        guard !isPlaying, !isCompleted else { return }

        isPlaying = true
        startTime = Date.now
        remainingTime = requiredDuration
        progress = 0.0
        statusText = "Watch the ad to unlock \(appName)... \(formatTime(remainingTime))"

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        // Ensure the timer fires during scroll-view tracking.
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// Called automatically when the countdown reaches zero. Sets completion
    /// flags and stops the timer.
    func onAdComplete() {
        isCompleted = true
        isPlaying = false
        canDismiss = true
        remainingTime = 0
        progress = 1.0
        statusText = "Ad complete! You earned 15 minutes of access."
        stopTimer()
    }

    /// Formats a raw seconds value into "M:SS" for display.
    ///
    /// - Parameter seconds: Non-negative integer seconds.
    /// - Returns: A string in the format "M:SS", e.g. "3:05".
    func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Tears down the timer. Safe to call multiple times or when no timer exists.
    func cleanup() {
        stopTimer()
    }

    // MARK: - Private Helpers

    /// One-second tick handler. Calculates elapsed time from `startTime` to
    /// guard against accumulated timer drift, then updates UI state.
    private func tick() {
        guard let startTime, isPlaying else { return }

        let elapsed = Date.now.timeIntervalSince(startTime)
        let remaining = max(requiredDuration - Int(elapsed), 0)

        remainingTime = remaining
        progress = min(elapsed / Double(requiredDuration), 1.0)
        statusText = remaining > 0
            ? "Watch the ad to unlock \(appName)... \(formatTime(remaining))"
            : statusText

        if remaining <= 0 {
            onAdComplete()
        }
    }

    /// Invalidates and nil-s out the timer.
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
