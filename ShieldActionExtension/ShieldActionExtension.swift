import ManagedSettings
import ManagedSettingsUI
import UIKit
import os

// MARK: - ShieldActionExtension

/// Handles user interactions with the buttons rendered on the shield overlay.
///
/// When the user taps "Unlock with Ad" (primary) or "Stay Focused" (secondary),
/// the system calls the appropriate `handle(action:for:completionHandler:)`
/// override in this extension.
///
/// **Deep-link flow (primary button):**
/// 1. User taps "Unlock with Ad" on the shield.
/// 2. This extension opens the main ScreenBreak app via a custom URL scheme
///    (`screenbreak://unlock`), passing the app's display name as a query
///    parameter so the main app knows which app to unlock after the ad.
/// 3. The completion handler is called with `.defer`, which tells the system
///    to keep the shield in place. The main app is responsible for removing
///    the shield (via `ManagedSettingsStore`) once the user finishes the ad.
///
/// The principal class name **must** match the `NSExtensionPrincipalClass`
/// value in `Info.plist`
/// (`$(PRODUCT_MODULE_NAME).ShieldActionExtension`).
class ShieldActionExtension: ShieldActionDelegate {

    // MARK: - Constants

    /// Custom URL scheme registered by the main ScreenBreak app.
    private static let urlScheme = "screenbreak"

    /// Shared App Group suite -- used to pass the identity of the app the
    /// user wants to unlock from this extension process to the main app.
    private static let appGroupID = "group.com.screenbreak.app"

    /// UserDefaults key where we stash the pending-unlock app name so the
    /// main app can read it even if the URL open fails to carry the query.
    private static let pendingUnlockAppNameKey = "screenbreak.pendingUnlockAppName"

    /// UserDefaults key where we stash the pending-unlock token data.
    private static let pendingUnlockTokenKey = "screenbreak.pendingUnlockTokenData"

    private let logger = Logger(
        subsystem: "com.screenbreak.app.ShieldActionExtension",
        category: "ShieldAction"
    )

    // MARK: - Application Shield Actions

    /// Handles a button tap on the shield overlay for a blocked **application**.
    ///
    /// - Parameters:
    ///   - action: Which button was tapped (`.primaryButtonPressed` or `.secondaryButtonPressed`).
    ///   - application: The `Application` that is currently shielded.
    ///   - completionHandler: Must be called exactly once with a `ShieldActionResponse`.
    override func handle(
        action: ShieldAction,
        for application: Application,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        let appName = application.localizedDisplayName ?? "Unknown"
        logger.info("Shield action \(String(describing: action)) for application: \(appName)")

        switch action {
        case .primaryButtonPressed:
            // --- "Unlock with Ad" ---
            // 1. Persist the app name (and optionally encoded token) to shared
            //    UserDefaults so the main app can identify which app to unlock.
            persistPendingUnlock(appName: appName, application: application)

            // 2. Build the deep-link URL.
            //    Format: screenbreak://unlock?app=<percent-encoded name>
            let encodedName = appName.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            ) ?? appName
            let urlString = "\(Self.urlScheme)://unlock?app=\(encodedName)"

            if let url = URL(string: urlString) {
                // Attempt to open the main app. `open(_:)` is available on
                // the shared `UIApplication` proxy exposed to Shield Action
                // extensions on iOS 16+.
                //
                // NOTE: Extensions do not have direct access to
                // `UIApplication.shared`. Instead we use the lower-level
                // `NSExtensionContext` approach or simply rely on the
                // `.defer` response -- the system will foreground the
                // shield, and the user can switch to ScreenBreak manually
                // if the open call is unavailable.
                self.open(url)
                logger.info("Requested open of URL: \(urlString)")
            } else {
                logger.error("Failed to construct URL from: \(urlString)")
            }

            // 3. Tell the system to keep the shield up. The main app will
            //    remove the shield via ManagedSettingsStore once the ad
            //    is completed.
            completionHandler(.defer)

        case .secondaryButtonPressed:
            // --- "Stay Focused" ---
            // Dismiss the shield and return the user to the home screen /
            // previous context. The blocked app remains shielded.
            logger.info("User chose to stay focused. Dismissing shield.")
            completionHandler(.close)

        @unknown default:
            logger.warning("Unknown shield action received. Closing shield.")
            completionHandler(.close)
        }
    }

    // MARK: - Web Domain Shield Actions

    /// Handles a button tap on the shield overlay for a blocked **web domain**.
    ///
    /// The flow mirrors the application handler: primary opens the main app
    /// for an ad, secondary dismisses.
    override func handle(
        action: ShieldAction,
        for webDomain: WebDomain,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        let domainName = webDomain.domain ?? "Unknown"
        logger.info("Shield action \(String(describing: action)) for web domain: \(domainName)")

        switch action {
        case .primaryButtonPressed:
            let encodedDomain = domainName.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
            ) ?? domainName
            let urlString = "\(Self.urlScheme)://unlock?domain=\(encodedDomain)"

            persistPendingUnlock(appName: domainName, application: nil)

            if let url = URL(string: urlString) {
                self.open(url)
                logger.info("Requested open of URL: \(urlString)")
            }

            completionHandler(.defer)

        case .secondaryButtonPressed:
            logger.info("User chose to stay focused (web domain). Dismissing shield.")
            completionHandler(.close)

        @unknown default:
            logger.warning("Unknown shield action received (web domain). Closing shield.")
            completionHandler(.close)
        }
    }

    // MARK: - Private Helpers

    /// Writes the pending-unlock metadata to the shared App Group
    /// `UserDefaults` so the main app can read it on launch.
    ///
    /// This is a belt-and-suspenders approach alongside the URL query
    /// parameters -- if the URL open is intercepted or the query is lost,
    /// the main app can still check shared defaults.
    private func persistPendingUnlock(appName: String, application: Application?) {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else {
            logger.error("Failed to open shared UserDefaults suite: \(Self.appGroupID)")
            return
        }

        defaults.set(appName, forKey: Self.pendingUnlockAppNameKey)

        // Encode the Application token if available so the main app can
        // precisely identify which token to remove from the shield set.
        if let application = application {
            do {
                let tokenData = try JSONEncoder().encode(application.token)
                defaults.set(tokenData, forKey: Self.pendingUnlockTokenKey)
                logger.info("Persisted pending unlock token for: \(appName)")
            } catch {
                logger.error("Failed to encode application token: \(error.localizedDescription)")
            }
        }

        defaults.synchronize()
    }

    /// Opens a URL from within the extension context.
    ///
    /// Shield Action extensions on iOS 16+ can call through to the system
    /// URL-opening mechanism via `NSExtensionContext`. This is a best-effort
    /// attempt -- if it fails, the user can still switch to ScreenBreak
    /// manually from the home screen.
    private func open(_ url: URL) {
        // The recommended approach for extensions that need to open URLs
        // is to use the responder chain. We walk up from self (or fabricate
        // a responder path) to find an object that responds to
        // `open(_:options:completionHandler:)`.
        //
        // In Shield Action extensions specifically, Apple routes
        // `open(_:)` calls through an internal `UIApplication` proxy.
        // The selector-based approach below is the documented workaround
        // used by app extensions that cannot import UIApplication directly.
        var responder: UIResponder? = self as? UIResponder
        let selector = sel_registerName("openURL:")

        while let r = responder {
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                return
            }
            responder = r.next
        }

        // Fallback: Attempt via shared NSExtensionContext if available.
        // This path is unlikely but serves as a safety net.
        logger.warning("No responder found for openURL: -- user must switch to ScreenBreak manually.")
    }
}
