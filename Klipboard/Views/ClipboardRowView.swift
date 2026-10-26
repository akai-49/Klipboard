import AppKit
import ImageIO
import SwiftUI

struct ClipboardRowView: View {
    private static let thumbnailCache: NSCache<NSUUID, NSImage> = {
        let cache = NSCache<NSUUID, NSImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 5 * 1024 * 1024 // 5 MB cap for 64px thumbnails
        return cache
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    let item: ClipItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(item.previewText)
                    .lineLimit(1)
                    .font(.system(size: 13))
                HStack(spacing: 4) {
                    if let app = item.sourceApp {
                        Text(app)
                    }
                    Text(Self.relativeFormatter.localizedString(for: item.createdAt, relativeTo: Date()))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer()
            if item.isPinned {
                Image(systemName: "pin.fill").foregroundStyle(.secondary)
            }
            if item.isFavorite {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch item.type {
        case .image:
            if let image = cachedThumbnail(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                icon
            }
        case .color:
            if let text = item.text {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: text) ?? .gray)
                    .frame(width: 20, height: 20)
            } else {
                icon
            }
        case .file:
            if let url = item.fileURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                icon
            }
        default:
            icon
        }
    }

    private var icon: some View {
        Image(systemName: item.type.symbolName)
            .frame(width: 24, height: 24)
            .foregroundStyle(.secondary)
    }

    /// Downsamples image data to a 64x64px thumbnail (~16 KB RAM) instead of
    /// decoding the full multi-megabyte Retina bitmap into memory.
    private func cachedThumbnail(for item: ClipItem) -> NSImage? {
        let key = item.id as NSUUID
        if let cached = Self.thumbnailCache.object(forKey: key) {
            return cached
        }
        guard let data = item.payload as CFData?,
              let source = CGImageSourceCreateWithData(data, nil)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 64
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let thumb = NSImage(cgImage: cgImage, size: NSSize(width: 32, height: 32))
        let cost = cgImage.bytesPerRow * cgImage.height
        Self.thumbnailCache.setObject(thumb, forKey: key, cost: cost)
        return thumb
    }
}

private extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        s.removeAll { $0 == "#" }
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
