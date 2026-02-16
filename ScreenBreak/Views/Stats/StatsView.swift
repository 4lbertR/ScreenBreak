import SwiftUI
import SwiftData
import Charts

/// Statistics screen showing aggregated usage data across multiple time periods.
///
/// Includes total time saved, ad stats, unlock counts, streak tracking,
/// a daily unlock bar chart using Swift Charts, and a "most blocked apps" ranking.
/// Delegates data aggregation to the existing `StatsViewModel`.
struct StatsView: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext

    // MARK: - State

    @State private var viewModel = StatsViewModel()
    @State private var animateCharts = false

    // MARK: - Constants

    private let teal = Color(hex: 0x00BFA6)

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 20) {
                // Period selector
                periodPicker
                    .padding(.top, 8)

                // Hero: Total time saved
                totalTimeSavedCard

                // Stats grid
                statsGrid

                // Daily unlocks chart (Swift Charts)
                dailyUnlocksChart

                // Streak section
                streakSection

                // Most blocked apps
                mostBlockedAppsSection

                // Bottom spacer for tab bar
                Color.clear.frame(height: 90)
            }
            .padding(.horizontal, 20)
        }
        .background(Color(hex: 0x0A0A0F))
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            viewModel.loadStats(modelContext: modelContext)
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                animateCharts = true
            }
        }
        .onChange(of: viewModel.selectedPeriod) { _, _ in
            viewModel.loadStats(modelContext: modelContext)
        }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        Picker("Time Period", selection: $viewModel.selectedPeriod) {
            ForEach(StatsViewModel.TimePeriod.allCases, id: \.self) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .onAppear {
            UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(teal.opacity(0.25))
            UISegmentedControl.appearance().setTitleTextAttributes(
                [.foregroundColor: UIColor.white],
                for: .selected
            )
            UISegmentedControl.appearance().setTitleTextAttributes(
                [.foregroundColor: UIColor.white.withAlphaComponent(0.5)],
                for: .normal
            )
            UISegmentedControl.appearance().backgroundColor = UIColor.white.withAlphaComponent(0.05)
        }
    }

    // MARK: - Total Time Saved

    private var totalTimeSavedCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.subheadline)
                    .foregroundStyle(teal)

                Text("Total Time Saved")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()
            }

            Text(viewModel.totalTimeSaved.shortFormatted)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(timeSavedSubtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [teal.opacity(0.08), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [teal.opacity(0.3), teal.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .animation(.easeInOut, value: viewModel.selectedPeriod)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            StatCard(
                icon: "play.rectangle.fill",
                title: "Ads Watched",
                value: "\(viewModel.totalUnlocks)",
                size: .compact,
                accentColor: .orange
            )

            StatCard(
                icon: "timer",
                title: "Ad Time",
                value: viewModel.totalAdTimeWatched.shortFormatted,
                size: .compact,
                accentColor: .purple
            )

            StatCard(
                icon: "lock.open.fill",
                title: "Unlocks",
                value: "\(viewModel.totalUnlocks)",
                size: .compact,
                accentColor: .blue
            )

            StatCard(
                icon: "shield.fill",
                title: "Days Active",
                value: "\(viewModel.dailyChartData.count)",
                size: .compact,
                accentColor: teal
            )
        }
        .animation(.easeInOut, value: viewModel.selectedPeriod)
    }

    // MARK: - Daily Unlocks Chart (Swift Charts)

    private var dailyUnlocksChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Daily Unlocks")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(viewModel.selectedPeriod.rawValue)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }

            Chart {
                ForEach(viewModel.dailyChartData) { entry in
                    BarMark(
                        x: .value("Day", entry.label),
                        y: .value("Unlocks", animateCharts ? entry.value : 0)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [teal, teal.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(4)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                        .foregroundStyle(.white.opacity(0.4))
                    AxisGridLine()
                        .foregroundStyle(.white.opacity(0.06))
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .chartPlotStyle { plotArea in
                plotArea.background(Color.clear)
            }
            .frame(height: 180)
            .animation(.spring(response: 0.8, dampingFraction: 0.7), value: animateCharts)
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

    // MARK: - Streak Section

    private var streakSection: some View {
        HStack(spacing: 16) {
            // Streak ring
            CircularProgressView(
                progress: min(Double(viewModel.currentStreak) / 30.0, 1.0),
                lineWidth: 10,
                color: .orange,
                secondaryColor: .orange.opacity(0.2)
            ) {
                VStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text("\(viewModel.currentStreak)")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 90, height: 90)

            VStack(alignment: .leading, spacing: 8) {
                Text("Current Streak")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("\(viewModel.currentStreak) consecutive day\(viewModel.currentStreak == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))

                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text("Longest: \(viewModel.longestStreak) days")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer()
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
                        colors: [.orange.opacity(0.2), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    // MARK: - Most Blocked Apps

    @ViewBuilder
    private var mostBlockedAppsSection: some View {
        let appRanking = viewModel.mostBlockedApps

        if !appRanking.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Most Unlocked Apps")
                    .font(.headline)
                    .foregroundStyle(.white)

                ForEach(Array(appRanking.prefix(5).enumerated()), id: \.element.id) { index, entry in
                    mostBlockedAppRow(rank: index + 1, entry: entry)
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
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
            }
        }
    }

    private func mostBlockedAppRow(rank: Int, entry: StatsViewModel.AppUnlockCount) -> some View {
        let maxCount = viewModel.mostBlockedApps.first?.unlockCount ?? 1

        return HStack(spacing: 14) {
            // Rank badge
            Text("\(rank)")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(rank <= 3 ? teal : .white.opacity(0.4))
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(rank <= 3 ? teal.opacity(0.12) : .white.opacity(0.05))
                )

            // App icon placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(teal.opacity(0.08))
                    .frame(width: 34, height: 34)

                Image(systemName: "app.fill")
                    .font(.caption)
                    .foregroundStyle(teal.opacity(0.5))
            }

            Text(entry.appName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)

            Spacer()

            Text("\(entry.unlockCount) unlock\(entry.unlockCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))

            // Progress bar showing relative frequency
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(.white.opacity(0.06))

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(teal.opacity(0.5))
                        .frame(width: geometry.size.width * (Double(entry.unlockCount) / Double(maxCount)))
                }
            }
            .frame(width: 50, height: 4)
        }
    }

    // MARK: - Helpers

    private var timeSavedSubtitle: String {
        switch viewModel.selectedPeriod {
        case .today:   return "Saved from your phone today"
        case .week:    return "Saved this week -- keep going!"
        case .month:   return "Your monthly total"
        case .allTime: return "Total since you started"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        StatsView()
    }
    .modelContainer(for: [
        DailyStats.self,
        UnlockSession.self,
        UserProfile.self
    ], inMemory: true)
    .preferredColorScheme(.dark)
}
