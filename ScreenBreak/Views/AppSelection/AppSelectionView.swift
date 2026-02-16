import SwiftUI
import SwiftData
import FamilyControls

/// App selection screen where users choose which apps to block using
/// Apple's `FamilyActivityPicker`.
///
/// Displays currently blocked apps with toggle controls and an "Apply Changes"
/// button to push the selection to `ScreenTimeManager.applyShielding()`.
struct AppSelectionView: View {

    // MARK: - Environment

    @Environment(ScreenTimeManager.self) private var screenTimeManager
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \BlockedAppInfo.dateAdded, order: .reverse)
    private var blockedApps: [BlockedAppInfo]

    // MARK: - State

    @State private var showingPicker = false
    @State private var showingApplyConfirmation = false
    @State private var hasUnappliedChanges = false

    // MARK: - Constants

    private let teal = Color(hex: 0x00BFA6)

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 20) {
                // Header
                headerSection

                // Authorization warning (if needed)
                if !screenTimeManager.isAuthorized {
                    authorizationWarning
                }

                // Add apps button
                addAppsButton

                // Blocked apps count
                if screenTimeManager.selectedAppCount > 0 {
                    blockedAppsCountBadge
                }

                // Currently blocked apps list
                if !blockedApps.isEmpty {
                    blockedAppsList
                }

                // Apply changes button
                if hasUnappliedChanges || screenTimeManager.selectedAppCount > 0 {
                    applyChangesButton
                }

                // Bottom spacer for tab bar
                Color.clear.frame(height: 90)
            }
            .padding(.horizontal, 20)
        }
        .background(Color(hex: 0x0A0A0F))
        .navigationTitle("Block Apps")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .familyActivityPicker(
            isPresented: $showingPicker,
            selection: pickerBinding
        )
        .onChange(of: screenTimeManager.selectedApps) { _, _ in
            hasUnappliedChanges = true
        }
        .alert("Changes Applied", isPresented: $showingApplyConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your app blocking settings have been updated. \(screenTimeManager.selectedAppCount) app(s) are now being monitored.")
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose Apps to Block")
                .font(.system(.title3, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Select the apps you want to limit. When you try to open a blocked app, you'll need to watch an ad to earn temporary access.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: - Authorization Warning

    private var authorizationWarning: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 4) {
                Text("Screen Time Access Required")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Grant Screen Time permission to block apps.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Button("Grant") {
                Task {
                    try? await screenTimeManager.requestAuthorization()
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(teal, in: Capsule())
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.yellow.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.yellow.opacity(0.2), lineWidth: 1)
        }
    }

    // MARK: - Add Apps Button

    private var addAppsButton: some View {
        Button {
            showingPicker = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(teal.opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: "plus.app.fill")
                        .font(.title2)
                        .foregroundStyle(teal)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Select Apps & Categories")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("Tap to open the app picker")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [teal.opacity(0.3), teal.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(!screenTimeManager.isAuthorized)
        .opacity(screenTimeManager.isAuthorized ? 1 : 0.5)
    }

    // MARK: - Blocked Apps Count

    private var blockedAppsCountBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.fill")
                .foregroundStyle(teal)

            Text("\(screenTimeManager.selectedAppCount) app\(screenTimeManager.selectedAppCount == 1 ? "" : "s") selected")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))

            if !screenTimeManager.selectedApps.categoryTokens.isEmpty {
                Text("+ \(screenTimeManager.selectedApps.categoryTokens.count) categor\(screenTimeManager.selectedApps.categoryTokens.count == 1 ? "y" : "ies")")
                    .font(.caption)
                    .foregroundStyle(teal.opacity(0.7))
            }

            Spacer()

            if hasUnappliedChanges {
                Text("Unsaved")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Blocked Apps List

    private var blockedAppsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Managed Apps")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.leading, 4)

            ForEach(blockedApps) { app in
                blockedAppRow(app: app)
            }
        }
    }

    private func blockedAppRow(app: BlockedAppInfo) -> some View {
        HStack(spacing: 14) {
            // App icon placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(app.isEnabled ? teal.opacity(0.12) : .white.opacity(0.05))
                    .frame(width: 42, height: 42)

                Image(systemName: app.isEnabled ? "shield.checkered" : "shield.slash")
                    .font(.body)
                    .foregroundStyle(app.isEnabled ? teal : .white.opacity(0.3))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(app.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)

                Text(app.isEnabled ? "Blocking active" : "Paused")
                    .font(.caption)
                    .foregroundStyle(app.isEnabled ? teal.opacity(0.7) : .white.opacity(0.35))
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { app.isEnabled },
                set: { newValue in
                    app.isEnabled = newValue
                    hasUnappliedChanges = true
                    try? modelContext.save()
                }
            ))
            .toggleStyle(.switch)
            .tint(teal)
            .labelsHidden()
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

    // MARK: - Apply Changes Button

    private var applyChangesButton: some View {
        Button {
            applyChanges()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.body.weight(.semibold))

                Text("Apply Changes")
                    .font(.headline)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(hasUnappliedChanges ? teal : teal.opacity(0.5))
            )
            .shadow(color: teal.opacity(hasUnappliedChanges ? 0.3 : 0), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: showingApplyConfirmation)
    }

    // MARK: - Picker Binding

    /// Two-way binding between the `FamilyActivityPicker` and the manager's
    /// `selectedApps`, ensuring persistence after each selection change.
    private var pickerBinding: Binding<FamilyActivitySelection> {
        Binding(
            get: { screenTimeManager.selectedApps },
            set: { newSelection in
                screenTimeManager.selectedApps = newSelection
                screenTimeManager.saveSelection()
                hasUnappliedChanges = true
            }
        )
    }

    // MARK: - Actions

    private func applyChanges() {
        screenTimeManager.applyShielding()
        screenTimeManager.saveSelection()
        hasUnappliedChanges = false
        showingApplyConfirmation = true
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AppSelectionView()
    }
    .environment(ScreenTimeManager.shared)
    .modelContainer(for: [BlockedAppInfo.self], inMemory: true)
    .preferredColorScheme(.dark)
}
