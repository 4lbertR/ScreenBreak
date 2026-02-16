import SwiftUI
import SwiftData

/// Settings screen with grouped sections for profile, notifications,
/// ad configuration, account management, and data controls.
struct SettingsView: View {

    // MARK: - Environment

    @Environment(ScreenTimeManager.self) private var screenTimeManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    // MARK: - AppStorage

    @AppStorage("displayName") private var displayName: String = ""
    @AppStorage("dailyGoalMinutes") private var dailyGoalMinutes: Int = 120
    @AppStorage("notifyUnlockReminders") private var notifyUnlockReminders: Bool = true
    @AppStorage("notifyDailySummary") private var notifyDailySummary: Bool = true
    @AppStorage("notifyMotivationalQuotes") private var notifyMotivationalQuotes: Bool = false
    @AppStorage("useMockAds") private var useMockAds: Bool = true

    // MARK: - State

    @State private var showResetConfirmation = false
    @State private var showRemoveBlocksConfirmation = false
    @State private var showSyncSuccess = false
    @State private var isSyncing = false

    // Account fields
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isLoggedIn: Bool = false
    @State private var showLoginError = false

    // MARK: - Constants

    private let teal = Color(hex: 0x00BFA6)
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    private let goalOptions: [(String, Int)] = [
        ("30 minutes", 30),
        ("1 hour", 60),
        ("2 hours", 120),
        ("4 hours", 240),
        ("8 hours", 480)
    ]

    // MARK: - Body

    var body: some View {
        Form {
            // Profile section
            profileSection

            // Notifications section
            notificationsSection

            // Ad settings section
            adSettingsSection

            // Account section
            accountSection

            // About section
            aboutSection

            // Danger zone
            dangerZoneSection
        }
        .scrollContentBackground(.hidden)
        .background(Color(hex: 0x0A0A0F))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .tint(teal)
        .alert("Reset All Data", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset Everything", role: .destructive) {
                resetAllData()
            }
        } message: {
            Text("This will permanently delete all your statistics, unlock history, and settings. This action cannot be undone.")
        }
        .alert("Remove All Blocks", isPresented: $showRemoveBlocksConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove Blocks", role: .destructive) {
                removeAllBlocks()
            }
        } message: {
            Text("This will remove shields from all blocked apps. You can re-enable blocking at any time.")
        }
        .alert("Sync Complete", isPresented: $showSyncSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your data has been synced with the server.")
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        Section {
            // Display name
            HStack(spacing: 12) {
                settingsIcon("person.fill", color: teal)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Display Name")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))

                    TextField("Enter your name", text: $displayName)
                        .font(.body)
                        .foregroundStyle(.white)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                }
            }
            .listRowBackground(Color.white.opacity(0.04))
            .onChange(of: displayName) { _, newName in
                syncNameToProfile(newName)
            }

            // Daily goal
            HStack(spacing: 12) {
                settingsIcon("target", color: .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Goal")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))

                    Picker("Daily Goal", selection: $dailyGoalMinutes) {
                        ForEach(goalOptions, id: \.1) { label, value in
                            Text(label).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                    .labelsHidden()
                }

                Spacer()
            }
            .listRowBackground(Color.white.opacity(0.04))
            .onChange(of: dailyGoalMinutes) { _, newGoal in
                syncGoalToProfile(newGoal)
            }
        } header: {
            sectionHeader("Profile")
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        Section {
            toggleRow(
                icon: "bell.badge.fill",
                color: .red,
                title: "Unlock Reminders",
                subtitle: "Notify when unlocks are about to expire",
                isOn: $notifyUnlockReminders
            )

            toggleRow(
                icon: "chart.bar.doc.horizontal.fill",
                color: .blue,
                title: "Daily Summary",
                subtitle: "Evening recap of your progress",
                isOn: $notifyDailySummary
            )

            toggleRow(
                icon: "quote.bubble.fill",
                color: .purple,
                title: "Motivational Quotes",
                subtitle: "Periodic inspirational messages",
                isOn: $notifyMotivationalQuotes
            )
        } header: {
            sectionHeader("Notifications")
        }
    }

    // MARK: - Ad Settings Section

    private var adSettingsSection: some View {
        Section {
            toggleRow(
                icon: "play.rectangle.fill",
                color: .orange,
                title: "Use Mock Ads",
                subtitle: useMockAds
                    ? "Showing simulated ads (development)"
                    : "Showing real Google AdMob ads",
                isOn: $useMockAds
            )

            // Ad duration info
            HStack(spacing: 12) {
                settingsIcon("clock.arrow.circlepath", color: teal)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ad Escalation")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 3) {
                        adTierRow(label: "1st unlock", value: "1 min", color: teal)
                        adTierRow(label: "2nd unlock", value: "3 min", color: .yellow)
                        adTierRow(label: "3rd+ unlock", value: "5 min", color: .red)
                    }
                }

                Spacer()
            }
            .listRowBackground(Color.white.opacity(0.04))
        } header: {
            sectionHeader("Ad Settings")
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        Section {
            if isLoggedIn {
                // Logged in state
                HStack(spacing: 12) {
                    settingsIcon("person.crop.circle.badge.checkmark", color: .green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Logged In")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    Spacer()

                    Button("Sign Out") {
                        isLoggedIn = false
                        email = ""
                        password = ""
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                }
                .listRowBackground(Color.white.opacity(0.04))
            } else {
                // Email field
                HStack(spacing: 12) {
                    settingsIcon("envelope.fill", color: .blue)

                    TextField("Email", text: $email)
                        .font(.body)
                        .foregroundStyle(.white)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                }
                .listRowBackground(Color.white.opacity(0.04))

                // Password field
                HStack(spacing: 12) {
                    settingsIcon("lock.fill", color: .blue)

                    SecureField("Password", text: $password)
                        .font(.body)
                        .foregroundStyle(.white)
                        .textContentType(.password)
                }
                .listRowBackground(Color.white.opacity(0.04))

                // Login / Register buttons
                HStack(spacing: 12) {
                    Button {
                        performLogin()
                    } label: {
                        Text("Log In")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(teal, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        performRegister()
                    } label: {
                        Text("Register")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(teal)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(teal.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(Color.white.opacity(0.04))
            }

            // Sync button
            Button {
                syncWithServer()
            } label: {
                HStack(spacing: 12) {
                    settingsIcon("arrow.triangle.2.circlepath", color: teal)

                    Text("Sync with Server")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)

                    Spacer()

                    if isSyncing {
                        ProgressView()
                            .tint(teal)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.white.opacity(0.04))
            .disabled(isSyncing)
        } header: {
            sectionHeader("Account")
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            // App version
            HStack(spacing: 12) {
                settingsIcon("info.circle.fill", color: .gray)

                Text("Version")
                    .font(.subheadline)
                    .foregroundStyle(.white)

                Spacer()

                Text("\(appVersion) (\(buildNumber))")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .listRowBackground(Color.white.opacity(0.04))

            // Privacy policy
            Button {
                if let url = URL(string: "https://screenbreak.app/privacy") {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 12) {
                    settingsIcon("hand.raised.fill", color: .blue)

                    Text("Privacy Policy")
                        .font(.subheadline)
                        .foregroundStyle(.white)

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.white.opacity(0.04))

            // Rate app
            Button {
                if let url = URL(string: "https://apps.apple.com/app/id0000000000?action=write-review") {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 12) {
                    settingsIcon("star.fill", color: .yellow)

                    Text("Rate ScreenBreak")
                        .font(.subheadline)
                        .foregroundStyle(.white)

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.white.opacity(0.04))
        } header: {
            sectionHeader("About")
        }
    }

    // MARK: - Danger Zone Section

    private var dangerZoneSection: some View {
        Section {
            // Remove all blocks
            Button {
                showRemoveBlocksConfirmation = true
            } label: {
                HStack(spacing: 12) {
                    settingsIcon("shield.slash.fill", color: .orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remove All Blocks")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                        Text("Unshield all currently blocked apps")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.orange.opacity(0.04))

            // Reset all data
            Button {
                showResetConfirmation = true
            } label: {
                HStack(spacing: 12) {
                    settingsIcon("trash.fill", color: .red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset All Data")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.red)
                        Text("Permanently delete all statistics and history")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.red.opacity(0.04))
        } header: {
            sectionHeader("Danger Zone")
        }
    }

    // MARK: - Reusable Subviews

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.4))
            .textCase(.uppercase)
            .tracking(0.8)
    }

    private func settingsIcon(_ systemName: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(0.15))
                .frame(width: 30, height: 30)

            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    private func toggleRow(
        icon: String,
        color: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            settingsIcon(icon, color: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .tint(teal)
                .labelsHidden()
        }
        .listRowBackground(Color.white.opacity(0.04))
    }

    private func adTierRow(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
    }

    // MARK: - Actions

    private func syncNameToProfile(_ name: String) {
        let profile = UserProfile.fetchOrCreate(in: modelContext)
        profile.displayName = name
        try? modelContext.save()
    }

    private func syncGoalToProfile(_ goal: Int) {
        let profile = UserProfile.fetchOrCreate(in: modelContext)
        profile.dailyGoalMinutes = goal
        try? modelContext.save()
    }

    private func performLogin() {
        guard !email.isEmpty, !password.isEmpty else {
            showLoginError = true
            return
        }
        // Simulate login -- in production, call API
        isLoggedIn = true
    }

    private func performRegister() {
        guard !email.isEmpty, !password.isEmpty else {
            showLoginError = true
            return
        }
        // Simulate registration -- in production, call API
        isLoggedIn = true
    }

    private func syncWithServer() {
        isSyncing = true
        // Simulate network call
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isSyncing = false
            showSyncSuccess = true
        }
    }

    private func removeAllBlocks() {
        screenTimeManager.removeShielding()
    }

    private func resetAllData() {
        // Delete all SwiftData entities
        do {
            try modelContext.delete(model: DailyStats.self)
            try modelContext.delete(model: UnlockSession.self)
            try modelContext.delete(model: BlockedAppInfo.self)
            // Reset profile to defaults (keep the row, clear values)
            let profile = UserProfile.fetchOrCreate(in: modelContext)
            profile.streakDays = 0
            profile.longestStreak = 0
            profile.totalDaysUsing = 0
            try modelContext.save()
        } catch {
            // Log error in production
        }

        // Remove shields
        screenTimeManager.removeShielding()

        // Reset AppStorage values
        displayName = ""
        dailyGoalMinutes = 120
        notifyUnlockReminders = true
        notifyDailySummary = true
        notifyMotivationalQuotes = false
        useMockAds = true
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
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
