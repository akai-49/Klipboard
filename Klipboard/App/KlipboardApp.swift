import AppKit
import CoreServices
import Darwin

@main
enum KlipboardApp {
    static func main() {
        Prefs.registerDefaults()
        #if DEBUG
        ensureSingleInstanceAndCleanDerivedData()
        #else
        replaceOtherInstances()
        #endif

        let app = NSApplication.shared
        let delegate = MainActor.assumeIsolated { AppDelegate() }
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// Release builds: politely quit older copies of *this* app (same bundle ID) so the
    /// newest build owns the hotkey. Never kills or deletes anything else.
    private static func replaceOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID }
        guard !others.isEmpty else { return }
        others.forEach { $0.terminate() }
        // Give them up to 1s to exit and release the global hotkey.
        for _ in 0..<20 where others.contains(where: { !$0.isTerminated }) {
            usleep(50_000)
        }
    }

    /// Debug only: ensures only one Klipboard instance runs at a time and cleans up any iconless
    /// Xcode DerivedData builds so Spotlight only shows the active app bundle.
    private static func ensureSingleInstanceAndCleanDerivedData() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let currentBundleID = Bundle.main.bundleIdentifier ?? "com.abhishek.Klipboard"
        let knownBundleIDs: Set<String> = [
            currentBundleID,
            currentBundleID.lowercased(),
            "Kai.Klipboard"
        ]

        var killedAny = false
        for running in NSWorkspace.shared.runningApplications {
            let pid = running.processIdentifier
            guard pid != myPID, pid > 0 else { continue }
            let bundleID = running.bundleIdentifier ?? ""
            let name = running.localizedName ?? ""
            let execName = running.executableURL?.lastPathComponent ?? ""
            if knownBundleIDs.contains(bundleID) || name == "Klipboard" || execName == "Klipboard" {
                _ = kill(pid, SIGKILL)
                _ = running.forceTerminate()
                killedAny = true
            }
        }

        if killedAny {
            usleep(100_000) // Allow WindowServer/Carbon to release global hotkeys (⌥V / ⌘⇧V)
        }

        let currentBundleURL = Bundle.main.bundleURL.standardizedFileURL
        removeStaleBuilds(keeping: currentBundleURL, bundleIDs: knownBundleIDs)
    }

    private static func removeStaleBuilds(keeping currentBundleURL: URL, bundleIDs: Set<String>) {
        let fm = FileManager.default
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        var candidateApps = Set<URL>()

        for id in bundleIDs {
            if let urls = LSCopyApplicationURLsForBundleIdentifier(id as CFString, nil)?.takeRetainedValue() as? [URL] {
                for url in urls {
                    candidateApps.insert(url.standardizedFileURL)
                }
            }
        }

        let homeDir = fm.homeDirectoryForCurrentUser
        let derivedDataDir = homeDir.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        if fm.fileExists(atPath: derivedDataDir.path),
           let enumerator = fm.enumerator(
               at: derivedDataDir,
               includingPropertiesForKeys: [.isDirectoryKey],
               options: [.skipsPackageDescendants]
           ) {
            for case let url as URL in enumerator where url.lastPathComponent == currentBundleURL.lastPathComponent {
                candidateApps.insert(url.standardizedFileURL)
            }
        }

        for appURL in candidateApps where appURL != currentBundleURL {
            let path = appURL.path
            let iconPath = appURL.appendingPathComponent("Contents/Resources/AppIcon.icns").path
            let isDerivedOrTemp = path.contains("/DerivedData/") ||
                path.contains("/dmg-staging") ||
                path.contains("/.Trash/") ||
                path.contains("/dist/Klipboard.app")
            let isMissingIcon = !fm.fileExists(atPath: iconPath)

            if isDerivedOrTemp || isMissingIcon {
                unregisterFromLaunchServices(lsregisterPath: lsregister, appPath: path)
                if fm.fileExists(atPath: path) {
                    try? fm.removeItem(at: appURL)
                }
            }
        }

        if fm.isExecutableFile(atPath: lsregister) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: lsregister)
            proc.arguments = ["-f", currentBundleURL.path]
            try? proc.run()
            proc.waitUntilExit()
        }
    }

    private static func unregisterFromLaunchServices(lsregisterPath: String, appPath: String) {
        guard FileManager.default.isExecutableFile(atPath: lsregisterPath) else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: lsregisterPath)
        proc.arguments = ["-u", appPath]
        try? proc.run()
        proc.waitUntilExit()
    }
}
