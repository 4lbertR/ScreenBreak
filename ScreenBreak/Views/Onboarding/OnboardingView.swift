import SwiftUI

/// Multi-page onboarding flow presented on first launch.
///
/// Three pages introduce the user to ScreenBreak:
/// 1. **Welcome** - "Take Back Your Time" with app overview
/// 2. **How It Works** - Explains the escalating ad system (1min -> 3min -> 5min)
/// 3. **Get Started** - Request Screen Time permission and continue
///
/// Sets `hasCompletedOnboarding` to `true` when the user finishes.
struct OnboardingView: View {

    // MARK: - Bindings & Environment

    @Binding var hasCompletedOnboarding: Bool

    @Environment(ScreenTimeManager.self) private var screenTimeManager

    // MARK: - State

    @State private var currentPage: Int = 0
    @State private var isRequestingPermission: Bool = false
    @State private var permissionGranted: Bool = false
    @State private var showPermissionError: Bool = false

    // MARK: - Constants

    private let teal = Color(hex: 0x00BFA6)
    private let pageCount = 3

    // MARK: - Body

    var body: some View {
        ZStack {
            // Full-screen gradient background
            backgroundGradient

            VStack(spacing: 0) {
                // Page content
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    howItWorksPage.tag(1)
                    getStartedPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                // Bottom controls
                bottomControls
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(teal.opacity(0.12))
                    .frame(width: 140, height: 140)

                Circle()
                    .fill(teal.opacity(0.06))
                    .frame(width: 180, height: 180)

                Image(systemName: "iphone.slash")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(teal)
                    .symbolEffect(.pulse, options: .repeating)
            }
            .padding(.bottom, 16)

            // Title
            Text("Take Back\nYour Time")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            // Subtitle
            Text(AppConstants.Strings.onboardingSubtitle)
                .font(.body)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 24)

            // Feature highlights
            VStack(spacing: 14) {
                featureRow(icon: "shield.checkered", text: "Block distracting apps")
                featureRow(icon: "clock.badge.checkmark", text: "Earn access through commitment")
                featureRow(icon: "chart.line.uptrend.xyaxis", text: "Track your progress over time")
            }
            .padding(.top, 8)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Page 2: How It Works

    private var howItWorksPage: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 140, height: 140)

                Image(systemName: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(.orange)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(.bottom, 16)

            // Title
            Text("How It Works")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            // Subtitle
            Text("Want to open a blocked app? You'll need to watch an ad first. The more you try, the longer they get.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 16)

            // Escalation tiers
            VStack(spacing: 16) {
                escalationTier(
                    attempt: "1st unlock",
                    duration: "1 minute",
                    icon: "1.circle.fill",
                    color: teal
                )
                escalationTier(
                    attempt: "2nd unlock",
                    duration: "3 minutes",
                    icon: "2.circle.fill",
                    color: .yellow
                )
                escalationTier(
                    attempt: "3rd+ unlock",
                    duration: "5 minutes",
                    icon: "3.circle.fill",
                    color: .red
                )
            }
            .padding(.top, 4)

            Text("Each unlock gives you 15 minutes of access.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 4)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Page 3: Get Started

    private var getStartedPage: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(teal.opacity(0.12))
                    .frame(width: 140, height: 140)

                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(teal)
                    .symbolEffect(.bounce, value: permissionGranted)
            }
            .padding(.bottom, 16)

            // Title
            Text("Get Started")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            // Description
            Text("ScreenBreak needs Screen Time access to block and manage apps on your device. This stays on your device and is never shared.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 16)

            // Permission status
            if permissionGranted {
                Label("Permission Granted", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(teal)
                    .transition(.scale.combined(with: .opacity))
            } else {
                // Request permission button
                Button {
                    requestScreenTimePermission()
                } label: {
                    HStack(spacing: 10) {
                        if isRequestingPermission {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Image(systemName: "lock.shield")
                                .font(.body.weight(.semibold))
                        }
                        Text("Grant Screen Time Access")
                            .font(.headline)
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(teal, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(isRequestingPermission)
            }

            if showPermissionError {
                Text("Permission was denied. You can grant it later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .animation(.easeInOut, value: permissionGranted)
        .animation(.easeInOut, value: showPermissionError)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 20) {
            // Page indicators
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? teal : .white.opacity(0.25))
                        .frame(width: index == currentPage ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                }
            }

            // Navigation buttons
            HStack(spacing: 16) {
                if currentPage > 0 {
                    Button {
                        withAnimation { currentPage -= 1 }
                    } label: {
                        Text("Back")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                            )
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                Button {
                    handleNextAction()
                } label: {
                    Text(nextButtonTitle)
                        .font(.headline)
                        .foregroundStyle(canProceed ? .black : .white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(canProceed ? teal : .white.opacity(0.08))
                        )
                }
                .disabled(!canProceed)
            }
            .animation(.easeInOut(duration: 0.2), value: currentPage)
        }
    }

    // MARK: - Subviews

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(teal)
                .frame(width: 28)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

            Spacer()
        }
    }

    private func escalationTier(
        attempt: String,
        duration: String,
        icon: String,
        color: Color
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(attempt)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Watch a \(duration) ad")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Text(duration)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.08))
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        ZStack {
            Color(hex: 0x0A0A0F)
                .ignoresSafeArea()

            // Subtle radial glow
            RadialGradient(
                gradient: Gradient(colors: [
                    teal.opacity(0.08),
                    .clear
                ]),
                center: .top,
                startRadius: 100,
                endRadius: 500
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Logic

    private var nextButtonTitle: String {
        switch currentPage {
        case 0, 1: return "Continue"
        case 2:    return permissionGranted ? "Let's Go" : "Skip for Now"
        default:   return "Continue"
        }
    }

    private var canProceed: Bool {
        switch currentPage {
        case 0, 1: return true
        case 2:    return true // Always allow skipping
        default:   return true
        }
    }

    private func handleNextAction() {
        if currentPage < pageCount - 1 {
            withAnimation {
                currentPage += 1
            }
        } else {
            // Complete onboarding
            withAnimation(.easeInOut(duration: 0.3)) {
                hasCompletedOnboarding = true
            }
        }
    }

    private func requestScreenTimePermission() {
        isRequestingPermission = true
        showPermissionError = false

        Task {
            do {
                try await screenTimeManager.requestAuthorization()
                await MainActor.run {
                    isRequestingPermission = false
                    permissionGranted = screenTimeManager.isAuthorized
                    if !permissionGranted {
                        showPermissionError = true
                    }
                }
            } catch {
                await MainActor.run {
                    isRequestingPermission = false
                    showPermissionError = true
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .environment(ScreenTimeManager.shared)
}
