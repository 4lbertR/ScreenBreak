import ManagedSettings
import ManagedSettingsUI
import UIKit
import os

// MARK: - ShieldActionExtension

class ShieldActionExtension: ShieldActionDelegate {

    private static let urlScheme = "screenbreak"
    private static let appGroupID = "group.com.screenbreak.app"
    private static let pendingUnlockAppNameKey = "screenbreak.pendingUnlockAppName"
    private static let pendingUnlockTokenKey = "screenbreak.pendingUnlockTokenData"

    private let logger = Logger(
        subsystem: "com.screenbreak.app.ShieldActionExtension",
        category: "ShieldAction"
    )

    // MARK: - Application Shield Actions

    func handle(
        action: ShieldAction,
        for application: Application,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        let appName = application.localizedDisplayName ?? "Unknown"
        logger.info("Shield action for application: \(appName, privacy: .public)")

        switch action {
        case .primaryButtonPressed:
            persistPendingUnlock(appName: appName, application: application)

            let encodedName = appName.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            ) ?? appName
            let urlString = "\(Self.urlScheme)://unlock?app=\(encodedName)"

            if let url = URL(string: urlString) {
                self.open(url)
            }

            completionHandler(.defer)

        case .secondaryButtonPressed:
            completionHandler(.close)

        @unknown default:
            completionHandler(.close)
        }
    }

    // MARK: - Web Domain Shield Actions

    func handle(
        action: ShieldAction,
        for webDomain: WebDomain,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        let domainName = webDomain.domain ?? "Unknown"
        logger.info("Shield action for web domain: \(domainName, privacy: .public)")

        switch action {
        case .primaryButtonPressed:
            let encodedDomain = domainName.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            ) ?? domainName
            let urlString = "\(Self.urlScheme)://unlock?domain=\(encodedDomain)"

            persistPendingUnlock(appName: domainName, application: nil)

            if let url = URL(string: urlString) {
                self.open(url)
            }

            completionHandler(.defer)

        case .secondaryButtonPressed:
            completionHandler(.close)

        @unknown default:
            completionHandler(.close)
        }
    }

    // MARK: - Private Helpers

    private func persistPendingUnlock(appName: String, application: Application?) {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else {
            return
        }

        defaults.set(appName, forKey: Self.pendingUnlockAppNameKey)

        if let application = application {
            do {
                let tokenData = try JSONEncoder().encode(application.token)
                defaults.set(tokenData, forKey: Self.pendingUnlockTokenKey)
            } catch {
                logger.error("Failed to encode application token")
            }
        }

        defaults.synchronize()
    }

    private func open(_ url: URL) {
        var responder: UIResponder? = self as? UIResponder
        let selector = sel_registerName("openURL:")

        while let r = responder {
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                return
            }
            responder = r.next
        }
    }
}
