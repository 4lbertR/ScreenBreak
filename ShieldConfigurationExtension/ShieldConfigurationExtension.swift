import ManagedSettings
import ManagedSettingsUI
import UIKit
import os

// MARK: - ShieldConfigurationExtension

class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    // MARK: - Brand Colors

    private static let brandTeal = UIColor(
        red: 0.00, green: 0.80, blue: 0.78, alpha: 1.0
    )
    private static let backgroundDark = UIColor(
        red: 0.07, green: 0.07, blue: 0.12, alpha: 1.0
    )
    private static let secondaryGrey = UIColor(
        red: 0.65, green: 0.65, blue: 0.70, alpha: 1.0
    )
    private static let subtitleWhite = UIColor(
        red: 0.90, green: 0.90, blue: 0.92, alpha: 1.0
    )

    private let logger = Logger(
        subsystem: "com.screenbreak.app.ShieldConfigurationExtension",
        category: "ShieldConfiguration"
    )

    // MARK: - Application Shield

    override func configuration(
        shielding application: Application
    ) -> ShieldConfiguration {
        let appName = application.localizedDisplayName ?? "This App"
        logger.info("Configuring shield for application: \(appName, privacy: .public)")

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

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        let appName = application.localizedDisplayName ?? "This App"
        let categoryName = category.localizedDisplayName ?? "this category"
        logger.info("Configuring shield for application: \(appName, privacy: .public) in category: \(categoryName, privacy: .public)")

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

    override func configuration(
        shielding webDomain: WebDomain
    ) -> ShieldConfiguration {
        let domainName = webDomain.domain ?? "this website"
        logger.info("Configuring shield for web domain: \(domainName, privacy: .public)")

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

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        let domainName = webDomain.domain ?? "This website"
        let categoryName = category.localizedDisplayName ?? "this category"
        logger.info("Configuring shield for web domain: \(domainName, privacy: .public) in category: \(categoryName, privacy: .public)")

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
