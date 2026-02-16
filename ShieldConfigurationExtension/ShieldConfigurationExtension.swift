import ManagedSettings
import ManagedSettingsUI
import UIKit
import os

// MARK: - ShieldConfigurationExtension

/// Provides the visual configuration for the shield overlay that iOS renders
/// on top of blocked applications and web domains.
///
/// The system instantiates this class in an extension process whenever a
/// shielded app or domain is launched. It calls the appropriate
/// `configuration(shielding:)` override and uses the returned
/// `ShieldConfiguration` to draw the overlay.
///
/// The principal class name **must** match the `NSExtensionPrincipalClass`
/// value in `Info.plist`
/// (`$(PRODUCT_MODULE_NAME).ShieldConfigurationExtension`).
class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    // MARK: - Brand Colors (UIKit equivalents of the SwiftUI palette)

    /// Primary brand teal -- used for the title text and primary button background.
    /// Matches `Color.brandTeal` (0.00, 0.80, 0.78) from the main app.
    private static let brandTeal = UIColor(
        red: 0.00, green: 0.80, blue: 0.78, alpha: 1.0
    )

    /// Very dark blue-grey background, matching `Color.backgroundDark`.
    private static let backgroundDark = UIColor(
        red: 0.07, green: 0.07, blue: 0.12, alpha: 1.0
    )

    /// Muted grey for the secondary "Stay Focused" button label.
    private static let secondaryGrey = UIColor(
        red: 0.65, green: 0.65, blue: 0.70, alpha: 1.0
    )

    /// Subtle off-white for body / subtitle text.
    private static let subtitleWhite = UIColor(
        red: 0.90, green: 0.90, blue: 0.92, alpha: 1.0
    )

    private let logger = Logger(
        subsystem: "com.screenbreak.app.ShieldConfigurationExtension",
        category: "ShieldConfiguration"
    )

    // MARK: - Application Shield

    /// Returns the custom shield configuration displayed when the user tries
    /// to open a blocked **application**.
    ///
    /// Layout:
    ///   - Dark blurred background with a solid dark fill underneath.
    ///   - Lock icon at the top.
    ///   - Title: "App Blocked" in brand teal.
    ///   - Subtitle explaining the unlock flow.
    ///   - Primary CTA: "Unlock with Ad" (teal button, white text).
    ///   - Secondary CTA: "Stay Focused" (text-only, grey).
    override func configuration(
        shielding application: Application
    ) -> ShieldConfiguration {
        logger.info("Configuring shield for application: \(application.localizedDisplayName ?? "Unknown")")

        let appName = application.localizedDisplayName ?? "This App"

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: Self.backgroundDark,
            icon: UIImage(systemName: "lock.shield.fill"),
            title: ShieldConfiguration.Label(
                text: "App Blocked",
                color: Self.brandTeal
            ),
            subtitle: ShieldConfiguration.Label(
                text: "\(appName) is blocked by ScreenBreak.\nWatch a short ad to unlock for 15 minutes.",
                color: Self.subtitleWhite
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Unlock with Ad",
                color: .white
            ),
            primaryButtonBackgroundColor: Self.brandTeal,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Stay Focused",
                color: Self.secondaryGrey
            )
        )
    }

    // MARK: - Application (with category)

    /// Returns the custom shield configuration for an application that was
    /// blocked via a **category** token rather than an individual app token.
    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        logger.info(
            "Configuring shield for application: \(application.localizedDisplayName ?? "Unknown") "
            + "in category: \(category.localizedDisplayName ?? "Unknown")"
        )

        let appName = application.localizedDisplayName ?? "This App"
        let categoryName = category.localizedDisplayName ?? "this category"

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: Self.backgroundDark,
            icon: UIImage(systemName: "lock.shield.fill"),
            title: ShieldConfiguration.Label(
                text: "App Blocked",
                color: Self.brandTeal
            ),
            subtitle: ShieldConfiguration.Label(
                text: "\(appName) is blocked because \(categoryName) is restricted.\nWatch a short ad to unlock for 15 minutes.",
                color: Self.subtitleWhite
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Unlock with Ad",
                color: .white
            ),
            primaryButtonBackgroundColor: Self.brandTeal,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Stay Focused",
                color: Self.secondaryGrey
            )
        )
    }

    // MARK: - Web Domain Shield

    /// Returns the custom shield configuration displayed when the user tries
    /// to visit a blocked **web domain** in Safari or a WebView.
    override func configuration(
        shielding webDomain: WebDomain
    ) -> ShieldConfiguration {
        logger.info("Configuring shield for web domain: \(webDomain.domain ?? "Unknown")")

        let domainName = webDomain.domain ?? "this website"

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: Self.backgroundDark,
            icon: UIImage(systemName: "globe.badge.chevron.backward"),
            title: ShieldConfiguration.Label(
                text: "Website Blocked",
                color: Self.brandTeal
            ),
            subtitle: ShieldConfiguration.Label(
                text: "\(domainName) is blocked by ScreenBreak.\nWatch a short ad to unlock for 15 minutes.",
                color: Self.subtitleWhite
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Unlock with Ad",
                color: .white
            ),
            primaryButtonBackgroundColor: Self.brandTeal,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Stay Focused",
                color: Self.secondaryGrey
            )
        )
    }

    // MARK: - Web Domain (with category)

    /// Returns the custom shield for a web domain blocked via a category.
    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        logger.info(
            "Configuring shield for web domain: \(webDomain.domain ?? "Unknown") "
            + "in category: \(category.localizedDisplayName ?? "Unknown")"
        )

        let domainName = webDomain.domain ?? "This website"
        let categoryName = category.localizedDisplayName ?? "this category"

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: Self.backgroundDark,
            icon: UIImage(systemName: "globe.badge.chevron.backward"),
            title: ShieldConfiguration.Label(
                text: "Website Blocked",
                color: Self.brandTeal
            ),
            subtitle: ShieldConfiguration.Label(
                text: "\(domainName) is blocked because \(categoryName) is restricted.\nWatch a short ad to unlock for 15 minutes.",
                color: Self.subtitleWhite
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Unlock with Ad",
                color: .white
            ),
            primaryButtonBackgroundColor: Self.brandTeal,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Stay Focused",
                color: Self.secondaryGrey
            )
        )
    }
}
