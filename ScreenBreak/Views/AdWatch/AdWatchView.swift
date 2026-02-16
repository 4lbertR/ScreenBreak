import SwiftUI
import SwiftData
import FamilyControls
import ManagedSettings

/// Full-screen ad watching view presented when the user wants to unlock a blocked app.
///
/// Shows a countdown timer, mock ad area, and progress indicator. The view cannot
/// be dismissed until the ad timer completes. After completion, it triggers the
/// actual app unlock through `ScreenTimeManager` and records the session.
///
/// ## Parameters
/// - `appName`: Display name of the app being unlocked
/// - `appToken`: Optional `ApplicationToken` for the actual Screen Time unlock
/// - `requiredDuration`: Ad watch time in seconds (60, 180, or 300)
/// - `unlockAttempt`: Which attempt this is (1st, 2nd, 3rd+) for display purposes
struct AdWatchView: View {

    // MARK: - Configuration

    let appName: String
    let appToken: ApplicationToken?
    let requiredDuration: Int
    let unlockAttempt: Int

    // MARK: - Environment

    @Environment(ScreenTimeManager.self) private var screenTimeManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var adState: AdState = .preparing
    @State private var remainingSeconds: Int
    @State private var totalElapsed: Int = 0
    @State private var adTimer: Timer?
    @State private var pulseAnimation = false
    @State private var showCompletionConfetti = false

    // MARK: - Constants

    private let teal = Color(hex: 0x00BFA6)

    // MARK: - Ad State Machine

    enum AdState: Equatable {
        case preparing
        case playing
        case completed
    }

    // MARK: - Init

    init(
        appName: String,
        appToken: ApplicationToken? = nil,
        requiredDuration: Int,
        unlockAttempt: Int = 1
    ) {
        self.appName = appName
        self.appToken = appToken
        self.requiredDuration = requiredDuration
        self.unlockAttempt = unlockAttempt
        self._remainingSeconds = State(initialValue: requiredDuration)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Full-screen dark background
            Color(hex: 0x080810)
                .ignoresSafeArea()

            // Subtle animated gradient
            RadialGradient(
                gradient: Gradient(colors: [
                    currentAccent.opacity(0.06),
                    .clear
                ]),
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with app info
                topBar
                    .padding(.top, 12)

                Spacer()

                // Central countdown circle
                countdownCircle
                    .padding(.vertical, 20)

                // Ad attempt info
                attemptInfo

                Spacer()

                // Mock ad area
                if adState == .playing {
                    mockAdArea
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Completion view
                if adState == .completed {
                    completionView
                        .transition(.scale.combined(with: .opacity))
                }

                Spacer()

                // Bottom action area
                bottomAction
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
        }
        .interactiveDismissDisabled(adState != .completed)
        .onAppear {
            startAdPlayback()
        }
        .onDisappear {
            adTimer?.invalidate()
        }
        .animation(.easeInOut(duration: 0.4), value: adState)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(spacing: 8) {
            // App being unlocked
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(teal.opacity(0.12))
                        .frame(width: 36, height: 36)

                    Image(systemName: "app.fill")
                        .font(.body)
                        .foregroundStyle(teal)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlocking")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                    Text(appName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }

                Spacer()

                // Status badge
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.12), in: Capsule())
            }
        }
    }

    // MARK: - Countdown Circle

    private var countdownCircle: some View {
        ZStack {
            // Outer glow ring
            if adState == .playing {
                Circle()
                    .stroke(currentAccent.opacity(0.08), lineWidth: 2)
                    .frame(width: 220, height: 220)
                    .scaleEffect(pulseAnimation ? 1.08 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                        value: pulseAnimation
                    )
            }

            // Progress ring
            CircularProgressView(
                progress: progress,
                lineWidth: 14,
                color: currentAccent,
                secondaryColor: currentAccent.opacity(0.2)
            ) {
                VStack(spacing: 4) {
                    if adState == .completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(teal)
                            .symbolEffect(.bounce, value: showCompletionConfetti)
                    } else {
                        // Time display
                        Text(formattedTime)
                            .font(.system(size: 42, design: .monospaced, weight: .bold))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())

                        Text(adState == .preparing ? "Get ready..." : "remaining")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .frame(width: 200, height: 200)
        }
    }

    // MARK: - Attempt Info

    private var attemptInfo: some View {
        VStack(spacing: 6) {
            Text(attemptLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))

            Text(durationExplanation)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Mock Ad Area

    private var mockAdArea: some View {
        VStack(spacing: 10) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.white.opacity(0.08))

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [currentAccent, currentAccent.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress)
                        .animation(.linear(duration: 1), value: progress)
                }
            }
            .frame(height: 4)

            // Mock ad rectangle
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: 0x1A1A24))

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)

                VStack(spacing: 12) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.15))

                    Text("Ad playing...")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.3))

                    // Simulated ad content bars
                    VStack(spacing: 6) {
                        shimmerBar(width: 0.7)
                        shimmerBar(width: 0.5)
                        shimmerBar(width: 0.8)
                    }
                    .padding(.horizontal, 40)
                }
            }
            .frame(height: 160)
        }
    }

    // MARK: - Completion View

    private var completionView: some View {
        VStack(spacing: 16) {
            // Success icon
            ZStack {
                Circle()
                    .fill(teal.opacity(0.12))
                    .frame(width: 64, height: 64)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(teal)
            }

            Text("App Unlocked!")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.white)

            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.caption)
                    .foregroundStyle(teal)

                Text("Access granted for 15 minutes")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(teal.opacity(0.08), in: Capsule())
        }
    }

    // MARK: - Bottom Action

    @ViewBuilder
    private var bottomAction: some View {
        switch adState {
        case .preparing:
            VStack(spacing: 8) {
                ProgressView()
                    .tint(teal)
                Text("Loading ad...")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }

        case .playing:
            VStack(spacing: 8) {
                // Cannot dismiss message
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                    Text("Stay on this screen until the ad finishes")
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.3))

                // Elapsed time
                Text("Watched: \(formatElapsed(totalElapsed)) of \(formatElapsed(requiredDuration))")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.2))
            }

        case .completed:
            Button {
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.body.weight(.semibold))
                    Text("Done")
                        .font(.headline)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(teal, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: teal.opacity(0.3), radius: 16, y: 6)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: adState)
        }
    }

    // MARK: - Subviews

    private func shimmerBar(width fraction: CGFloat) -> some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.white.opacity(0.06))
                .frame(width: geometry.size.width * fraction, height: 8)
        }
        .frame(height: 8)
    }

    // MARK: - Computed Properties

    private var progress: Double {
        guard requiredDuration > 0 else { return 1 }
        return Double(totalElapsed) / Double(requiredDuration)
    }

    private var formattedTime: String {
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private var currentAccent: Color {
        switch adState {
        case .preparing: return .white.opacity(0.3)
        case .playing:   return attemptColor
        case .completed: return teal
        }
    }

    private var attemptColor: Color {
        switch unlockAttempt {
        case 1:  return teal
        case 2:  return .yellow
        default: return .red
        }
    }

    private var attemptLabel: String {
        switch unlockAttempt {
        case 1:  return "1st Unlock Attempt"
        case 2:  return "2nd Unlock Attempt"
        default: return "\(unlockAttempt)th Unlock Attempt"
        }
    }

    private var durationExplanation: String {
        switch unlockAttempt {
        case 1:  return "Watch a 1-minute ad to unlock"
        case 2:  return "Ad duration increased to 3 minutes"
        default: return "Maximum ad duration: 5 minutes"
        }
    }

    private var statusText: String {
        switch adState {
        case .preparing: return "Preparing"
        case .playing:   return "Playing"
        case .completed: return "Complete"
        }
    }

    private var statusColor: Color {
        switch adState {
        case .preparing: return .white.opacity(0.5)
        case .playing:   return attemptColor
        case .completed: return teal
        }
    }

    // MARK: - Timer Logic

    private func startAdPlayback() {
        // Brief preparation delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            adState = .playing
            pulseAnimation = true

            adTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task { @MainActor in
                    tick()
                }
            }
            if let timer = adTimer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }

    private func tick() {
        guard adState == .playing else { return }

        if remainingSeconds > 0 {
            remainingSeconds -= 1
            totalElapsed += 1
        }

        if remainingSeconds <= 0 {
            completeAd()
        }
    }

    private func completeAd() {
        adTimer?.invalidate()
        adTimer = nil
        pulseAnimation = false

        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            adState = .completed
            showCompletionConfetti = true
        }

        // Perform the actual unlock
        performUnlock()
    }

    private func performUnlock() {
        // Unlock via ScreenTimeManager
        if let token = appToken {
            screenTimeManager.temporarilyUnlockApp(
                token: token,
                duration: TimeInterval(AppConstants.UnlockDuration.accessTime)
            )
        }

        // Record the unlock session
        let session = UnlockSession.create(
            appBundleID: "unknown",
            appName: appName,
            adDurationWatched: requiredDuration
        )
        modelContext.insert(session)

        // Update today's stats
        let todayStats = DailyStats.fetchOrCreateToday(in: modelContext)
        todayStats.recordUnlock(adSeconds: requiredDuration)

        try? modelContext.save()
    }

    // MARK: - Formatting

    private func formatElapsed(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        }
        return "\(secs)s"
    }
}

// MARK: - Preview

#Preview("1st Attempt - 60s") {
    AdWatchView(
        appName: "Instagram",
        requiredDuration: 10, // Short for preview
        unlockAttempt: 1
    )
    .environment(ScreenTimeManager.shared)
    .modelContainer(for: [
        UnlockSession.self,
        DailyStats.self
    ], inMemory: true)
}

#Preview("3rd Attempt - 300s") {
    AdWatchView(
        appName: "TikTok",
        requiredDuration: 5,
        unlockAttempt: 3
    )
    .environment(ScreenTimeManager.shared)
    .modelContainer(for: [
        UnlockSession.self,
        DailyStats.self
    ], inMemory: true)
}
