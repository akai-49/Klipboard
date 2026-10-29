import Foundation
import UniformTypeIdentifiers

/// Reports screenshots saved as files (⌘⇧3/4/5) by watching the user's screenshot folder.
/// macOS tags each one with the kMDItemIsScreenCapture extended attribute, so other
/// images dropped into the same folder are ignored.
@MainActor
final class ScreenshotWatcher {
    var onScreenshot: ((URL) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var folder: URL?
    private var seen = Set<String>()
    private var pendingScan: DispatchWorkItem?

    /// Delay after a folder change before scanning, so macOS has finished writing the file.
    var settleDelay: TimeInterval = 0.5

    /// Where macOS saves screenshots: Screenshot app → Options → Save to, else the Desktop.
    nonisolated static func screenshotFolder() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
           !location.isEmpty {
            let url = URL(fileURLWithPath: (location as NSString).expandingTildeInPath, isDirectory: true)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }
        return home.appendingPathComponent("Desktop", isDirectory: true)
    }

    func start(folder: URL = ScreenshotWatcher.screenshotFolder()) {
        if source != nil, self.folder == folder { return }
        stop()
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        self.folder = folder
        // Screenshots already in the folder are never imported.
        seen = Set(fileNames(in: folder))

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleScan() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        pendingScan?.cancel()
        pendingScan = nil
        source?.cancel()
        source = nil
        folder = nil
    }

    private func scheduleScan() {
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        pendingScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: work)
    }

    func scan() {
        guard let folder else { return }
        for name in fileNames(in: folder) where !seen.contains(name) {
            seen.insert(name)
            let url = folder.appendingPathComponent(name)
            if Self.isScreenshot(url) { onScreenshot?(url) }
        }
    }

    /// Visible files only: macOS writes to a hidden temp file, then renames it into place.
    private func fileNames(in folder: URL) -> [String] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.map(\.lastPathComponent)
    }

    nonisolated static func isScreenshot(_ url: URL) -> Bool {
        isImage(url) && getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0
    }

    /// Screen recordings are tagged as screen captures too; keep only images.
    nonisolated static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }
}
