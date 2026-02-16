import Foundation
import SwiftData
import FamilyControls
import ManagedSettings

/// Persists metadata about an app the user has chosen to block via Screen Time.
///
/// Because `FamilyActivitySelection` is not directly SwiftData-compatible we
/// store its encoded representation as opaque `Data` in `tokenData` and
/// provide helpers to round-trip through `AppSelectionData`.
@Model
final class BlockedAppInfo {

    // MARK: - Stored Properties

    @Attribute(.unique)
    var id: UUID

    /// The `FamilyActivitySelection` encoded via `AppSelectionData`.
    /// This blob lets us restore the exact token set needed by
    /// `ManagedSettingsStore` without a live picker.
    var tokenData: Data

    /// User-visible name (e.g. "Instagram").
    var displayName: String

    /// When the user first added this app to the block list.
    var dateAdded: Date

    /// Whether the block is currently enforced.  Toggling this off suspends
    /// the shield without removing the entry.
    var isEnabled: Bool

    // MARK: - Init

    init(
        id: UUID = UUID(),
        tokenData: Data,
        displayName: String,
        dateAdded: Date = .now,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.tokenData = tokenData
        self.displayName = displayName
        self.dateAdded = dateAdded
        self.isEnabled = isEnabled
    }

    // MARK: - Convenience

    /// Creates a `BlockedAppInfo` directly from a `FamilyActivitySelection`.
    /// Returns `nil` if encoding fails.
    static func from(
        selection: FamilyActivitySelection,
        displayName: String
    ) -> BlockedAppInfo? {
        guard let wrapper = try? AppSelectionData(selection: selection),
              let encoded = try? JSONEncoder().encode(wrapper) else {
            return nil
        }
        return BlockedAppInfo(tokenData: encoded, displayName: displayName)
    }

    /// Decodes the stored token data back into a `FamilyActivitySelection`.
    func decodedSelection() -> FamilyActivitySelection? {
        guard let wrapper = try? JSONDecoder().decode(
            AppSelectionData.self,
            from: tokenData
        ) else {
            return nil
        }
        return wrapper.selection
    }
}

// MARK: - AppSelectionData

/// A lightweight `Codable` wrapper around `FamilyActivitySelection`.
///
/// `FamilyActivitySelection` itself conforms to `Codable` as of iOS 16+,
/// so this struct simply provides a named, versioned envelope we control,
/// making migration straightforward if Apple changes the underlying encoding.
struct AppSelectionData: Codable, Sendable {

    // MARK: - Versioning

    /// Bump this if the internal layout changes so old data can be migrated.
    static let currentVersion: Int = 1
    let version: Int

    // MARK: - Payload

    /// The actual Screen Time selection (application tokens, category tokens, etc.).
    let selection: FamilyActivitySelection

    // MARK: - Init

    init(selection: FamilyActivitySelection, version: Int = Self.currentVersion) throws {
        self.version = version
        self.selection = selection
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case version
        case selectionData
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)

        // Encode the selection separately so we own the top-level structure.
        let innerData = try JSONEncoder().encode(selection)
        try container.encode(innerData, forKey: .selectionData)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)

        let innerData = try container.decode(Data.self, forKey: .selectionData)
        selection = try JSONDecoder().decode(
            FamilyActivitySelection.self,
            from: innerData
        )
    }
}
