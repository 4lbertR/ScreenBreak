import Foundation
import FamilyControls
import ManagedSettings
import SwiftUI

@Observable
@MainActor
class AppSelectionViewModel {

    // MARK: - Public State

    /// Controls the presentation of the `FamilyActivityPicker` sheet.
    var isPickerPresented: Bool = false

    /// The current selection from the FamilyActivityPicker.
    var selectedApps: FamilyActivitySelection = FamilyActivitySelection()

    /// Human-readable display names of all blocked apps (derived from `BlockedAppInfo`).
    var blockedAppNames: [String] = []

    /// Total number of apps currently selected for blocking.
    var blockedAppsCount: Int = 0

    /// `true` while an apply/save operation is in progress.
    var isApplying: Bool = false

    /// Flipped to `true` after a successful apply so the UI can show a confirmation alert.
    var showSuccessAlert: Bool = false

    /// Non-nil when the last operation encountered an error.
    var errorMessage: String?

    // MARK: - Dependencies

    private let screenTimeManager = ScreenTimeManager.shared

    // MARK: - Load Current Selection

    /// Reads the persisted selection from `ScreenTimeManager` and synchronises
    /// local state so the picker and list reflect what is already blocked.
    func loadCurrentSelection() {
        screenTimeManager.loadSelection()
        selectedApps = screenTimeManager.selectedApps
        blockedAppsCount = screenTimeManager.selectedAppCount

        // Derive display names from token count -- FamilyControls tokens are
        // opaque so we use the count for the summary and rely on any saved
        // `BlockedAppInfo` rows for individual names.
        updateBlockedAppNames()
    }

    // MARK: - Apply Selection

    /// Persists the current `selectedApps` to `ScreenTimeManager`, applies
    /// shields, and saves the selection for future launches.
    func applySelection() {
        isApplying = true
        errorMessage = nil

        // Push the selection into the manager.
        screenTimeManager.selectedApps = selectedApps
        screenTimeManager.saveSelection()
        screenTimeManager.applyShielding()

        // Update local bookkeeping.
        blockedAppsCount = screenTimeManager.selectedAppCount
        updateBlockedAppNames()

        isApplying = false
        showSuccessAlert = true
    }

    // MARK: - Remove App

    /// Removes a single app from the blocked list by index in `blockedAppNames`.
    ///
    /// Because `FamilyActivitySelection` tokens are opaque sets we cannot remove
    /// by name; instead we rebuild the token set minus the one at the given index.
    /// This works when `blockedAppNames` is aligned 1-to-1 with the ordered token
    /// array (which it is, via `updateBlockedAppNames`).
    func removeApp(at index: Int) {
        guard index >= 0, index < blockedAppNames.count else { return }

        // Convert the token set to an ordered array, remove the element, rebuild.
        var tokens = Array(selectedApps.applicationTokens)
        guard index < tokens.count else { return }
        tokens.remove(at: index)
        selectedApps.applicationTokens = Set(tokens)

        // Re-apply.
        applySelection()
    }

    // MARK: - Clear All

    /// Removes every app from the selection and clears all shields.
    func clearAll() {
        selectedApps = FamilyActivitySelection()
        screenTimeManager.selectedApps = selectedApps
        screenTimeManager.saveSelection()
        screenTimeManager.removeShielding()

        blockedAppsCount = 0
        blockedAppNames = []
    }

    // MARK: - Present Picker

    /// Triggers presentation of the `FamilyActivityPicker` sheet.
    func presentPicker() {
        isPickerPresented = true
    }

    // MARK: - Private Helpers

    /// Builds a list of display-friendly names from the current selection.
    ///
    /// `ApplicationToken` does not expose a human-readable name directly, so we
    /// generate placeholder labels ("App 1", "App 2", ...) indexed by token order.
    /// In a production build this would be enhanced by cross-referencing the
    /// `BlockedAppInfo` table or the system app catalog.
    private func updateBlockedAppNames() {
        let tokenCount = selectedApps.applicationTokens.count
        let categoryCount = selectedApps.categoryTokens.count

        var names: [String] = []

        // Application tokens.
        for i in 0..<tokenCount {
            names.append("Blocked App \(i + 1)")
        }

        // Category tokens (if any).
        for i in 0..<categoryCount {
            names.append("Category \(i + 1)")
        }

        blockedAppNames = names
    }
}
