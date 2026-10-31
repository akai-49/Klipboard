import Foundation

enum WelcomePromptReason: Equatable {
    case firstLaunch
    case accessibilityNeeded
}

enum WelcomeLogic {
    /// Decides whether the welcome or permissions window should be shown on app launch.
    static func launchAction(hasCompletedWelcome: Bool, isAccessibilityTrusted: Bool) -> WelcomePromptReason? {
        if !hasCompletedWelcome {
            return .firstLaunch
        } else if !isAccessibilityTrusted {
            return .accessibilityNeeded
        } else {
            return nil
        }
    }

    /// Decides whether the permissions window should be shown when a paste is attempted.
    static func shouldPromptOnPaste(isAccessibilityTrusted: Bool) -> Bool {
        !isAccessibilityTrusted
    }

    /// Determines if an existing user upgrading from a pre-welcome version should be migrated.
    static func shouldMigrateExistingUser(didFirstLaunch: Bool, hasCompletedWelcomeObject: Any?) -> Bool {
        didFirstLaunch && hasCompletedWelcomeObject == nil
    }

    /// Whether the window should automatically close when accessibility is granted.
    static func shouldAutoCloseOnAccessibilityGranted(for reason: WelcomePromptReason) -> Bool {
        reason == .accessibilityNeeded
    }
}
