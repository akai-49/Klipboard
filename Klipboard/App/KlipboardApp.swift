import AppKit
import CoreServices
import Darwin

@main
enum KlipboardApp {
    static func main() {
        cleanupStaleInstancesAndDuplicates()

        let app = NSApplication.shared
        let delegate = MainActor.assumeIsolated { AppDelegate() }
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// Terminates any orphaned/older Klipboard processes (such as PID 52021 or old /Applications/Klipboard.app)
    /// and removes duplicate/iconless app bundles so Spotlight only shows one working Klipboard with the logo.
    private static func cleanupStaleInstancesAndDuplicates() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let legacyBundleIDs: Set<String> = [
            "com.abhishek.klipboard",
            "com.abhishek.Klipboard",
            "Kai.Klipboard"
        ]

        var killedAny = false
        for running in NSWorkspace.shared.runningApplications {
            let pid = running.processIdentifier
            guard pid != myPID, pid > 0 else { continue }
            let bundleID = running.bundleIdentifier ?? ""
            let name = running.localizedName ?? ""
            let execName = running.executableURL?.lastPathComponent ?? ""
            if legacyBundleIDs.contains(bundleID) || name == "Klipboard" || execName == "Klipboard" {
                _ = kill(pid, SIGKILL)
                _ = running.forceTerminate()
                killedAny = true
            }
        }

        if killedAny {
            usleep(100_000) // Allow WindowServer/Carbon to release global hotkeys (⌥V / ⌘⇧V)
        }

        let currentBundleURL = Bundle.main.bundleURL.standardizedFileURL
        removeDuplicateAppBundles(keeping: currentBundleURL, bundleIDs: legacyBundleIDs)
    }

    private static func removeDuplicateAppBundles(keeping currentBundleURL: URL, bundleIDs: Set<String>) {
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

        let realHome = URL(fileURLWithPath: "/Users/\(NSUserName())")
        let derivedDataRoots: [URL] = [
            realHome.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
            realHome.appendingPathComponent(".gemini/users"),
            URL(fileURLWithPath: "/Users/abhishek/Clipboard/Klipboard/build"),
            URL(fileURLWithPath: "/Users/abhishek/Clipboard/Klipboard/dist")
        ]

        for root in derivedDataRoots where fm.fileExists(atPath: root.path) {
            if let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants]
            ) {
                for case let url as URL in enumerator where url.lastPathComponent == "Klipboard.app" {
                    candidateApps.insert(url.standardizedFileURL)
                }
            }
        }

        let explicitLocations: [URL] = [
            URL(fileURLWithPath: "/Applications/Klipboard.app"),
            URL(fileURLWithPath: "/Users/abhishek/Clipboard/Klipboard/dist/Klipboard.app"),
            URL(fileURLWithPath: "/Users/abhishek/Clipboard/Klipboard/Klipboard.app"),
            realHome.appendingPathComponent("Applications/Klipboard.app"),
            realHome.appendingPathComponent("Downloads/Klipboard.app"),
            realHome.appendingPathComponent(".Trash/Klipboard.app")
        ]
        for loc in explicitLocations {
            candidateApps.insert(loc.standardizedFileURL)
        }

        for appURL in candidateApps where appURL != currentBundleURL {
            let path = appURL.path
            unregisterFromLaunchServices(lsregisterPath: lsregister, appPath: path)
            if fm.fileExists(atPath: path) {
                try? fm.removeItem(at: appURL)
            }
        }

        // Register the active bundle with the logo cleanly
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
