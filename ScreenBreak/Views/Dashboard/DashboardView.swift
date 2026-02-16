import SwiftUI
import SwiftData

/// The main dashboard screen showing today's progress, active unlocks,
/// motivational quotes, and a weekly summary chart.
///
/// Uses the existing `DashboardViewModel` (in ViewModels/) for business logic
/// and timer management, with SwiftData queries for persistent statistics.
struct DashboardView: View {

    // MARK: - Environment & State

    @Environment(ScreenTimeManager.self) private var screenTimeManager
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \UnlockSession.unlockedAt, order: .reverse)
    private var allUnlockSessions: [UnlockSession]

    @State private var viewModel = DashboardViewModel()
    @State private var currentQuote: String = AppConstants.Strings.motivationalQuotes.first ?? ""
    @State private var quoteTimer: Timer?

    // MARK: - Constants

    private let teal = Color(hex: 0x00BFA6)

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 20) {
                // Greeting header
                greetingHeader
                    .padding(.top, 8)

                // Today's progress card
                todaysProgressCard

                // Active unlocks
                activeUnlocksSection

                // Weekly chart
                weeklyChartCard

                // Motivational quote
                motivationalQuoteCard

                // Bottom spacer for tab bar
                Color.clear.frame(height: 90)
            }
            .padding(.horizontal, 20)
        }
        .background(Color(hex: 0x0A0A0F))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.loadData(modelContext: modelContext)
            viewModel.startRefreshTimer()
            rotateQuote()
            startQuoteTimer()
        }
        .onDisappear {
            viewModel.stopRefreshTimer()
            quoteTimer?.invalidate()
            quoteTimer = nil
        }
    }

    // MARK: - Greeting Header

    private var greetingHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingText)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)

                let profile = UserProfile.fetchOrCreate(in: modelContext)
                if !profile.displayName.isEmpty {
                    Text(profile.displayName)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(teal)
                }
            }

            Spacer()

            // Streak badge
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .symbolEffect(.variableColor.iterative, options: .repeating)

                Text("\(viewModel.currentStreak)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(.orange.opacity(0.12))
            }
        }
    }

    // MARK: - Today's Progress Card

    private var todaysProgressCard: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Today's Progress")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(todayDateString)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }

            HStack(spacing: 24) {
                // Circular progress ring
                CircularProgressView(
                    progress: viewModel.dailyGoalProgress,
                    lineWidth: 10,
                    color: teal
                ) {
                    VStack(spacing: 2) {
                        Text("\(Int(viewModel.dailyGoalProgress * 100))%")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                        Text("of goal")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .frame(width: 100, height: 100)

                // Stats column
                VStack(alignment: .leading, spacing: 12) {
                    miniStat(
                        icon: "clock.fill",
                        label: "Time Saved",
                        value: viewModel.todayTimeSaved.shortFormatted,
                        color: teal
                    )
                    miniStat(
                        icon: "lock.open.fill",
                        label: "Unlocks",
                        value: "\(viewModel.todayUnlockCount)",
                        color: .purple
                    )
                    miniStat(
                        icon: "play.rectangle.fill",
                        label: "Ad Time",
                        value: viewModel.todayAdTimeWatched.shortFormatted,
                        color: .orange
                    )
                }
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.1), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    // MARK: - Active Unlocks Section

    @ViewBuilder
    private var activeUnlocksSection: some View {
        let active = viewModel.activeUnlocks
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "lock.open.fill")
                        .foregroundStyle(teal)
                    Text("Active Unlocks")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(active.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(teal)
                }

                ForEach(active) { unlock in
                    activeUnlockRow(unlock: unlock)
                }
            }
        }
    }

    private func activeUnlockRow(unlock: DashboardViewModel.ActiveUnlock) -> some View {
        HStack(spacing: 14) {
            // App icon placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(teal.opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: "app.fill")
                    .font(.title3)
                    .foregroundStyle(teal.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(unlock.appName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Unlocked")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            // Countdown timer
            let remaining = unlock.remainingSeconds
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.caption)
                    .foregroundStyle(remaining < 120 ? .red : teal)

                Text(formatCountdown(remaining))
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                    .foregroundStyle(remaining < 120 ? .red : .white)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(remaining < 120 ? .red.opacity(0.12) : teal.opacity(0.08))
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        }
    }

    // MARK: - Weekly Chart Card

    private var weeklyChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("This Week")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("Time Saved")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }

            // Bar chart
            let weekData = viewModel.weeklyData
            let maxTimeSaved = weekData.map(\.timeSaved).max() ?? 1

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(weekData.indices, id: \.self) { index in
                    let entry = weekData[index]
                    let normalizedHeight = maxTimeSaved > 0
                        ? entry.timeSaved / maxTimeSaved
                        : 0

                    VStack(spacing: 6) {
                        // Bar
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [teal, teal.opacity(0.5)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(
                                height: max(4, normalizedHeight * 120)
                            )
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.7)
                                    .delay(Double(index) * 0.05),
                                value: normalizedHeight
                            )

                        // Day label
                        Text(entry.dayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 150)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        }
    }

    // MARK: - Motivational Quote

    private var motivationalQuoteCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "quote.opening")
                .font(.title2)
                .foregroundStyle(teal.opacity(0.5))

            Text(currentQuote)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [teal.opacity(0.2), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    // MARK: - Helpers

    private func miniStat(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
        }
    }

    private func formatCountdown(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:  return "Good Morning"
        case 12..<17: return "Good Afternoon"
        case 17..<22: return "Good Evening"
        default:      return "Good Night"
        }
    }

    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: .now)
    }

    private func rotateQuote() {
        if let quote = AppConstants.Strings.motivationalQuotes.randomElement() {
            withAnimation(.easeInOut(duration: 0.5)) {
                currentQuote = quote
            }
        }
    }

    private func startQuoteTimer() {
        quoteTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in
                rotateQuote()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DashboardView()
    }
    .environment(ScreenTimeManager.shared)
    .modelContainer(for: [
        UserProfile.self,
        DailyStats.self,
        UnlockSession.self,
        BlockedAppInfo.self
    ], inMemory: true)
    .preferredColorScheme(.dark)
}
