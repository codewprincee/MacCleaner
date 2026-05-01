import Foundation
import SwiftUI

/// Classification of a large file by extension. Drives icon, accent color, and the
/// kind-filter chips in `LargeFilesView`.
enum LargeFileKind: String, CaseIterable, Hashable, Sendable {
    case video = "Videos"
    case archive = "Archives"
    case diskImage = "Disk Images"
    case installer = "Installers"
    case document = "Documents"
    case backup = "Backups"
    case other = "Other"

    var symbol: String {
        switch self {
        case .video: return "play.rectangle.fill"
        case .archive: return "archivebox.fill"
        case .diskImage: return "opticaldiscdrive.fill"
        case .installer: return "shippingbox.fill"
        case .document: return "doc.richtext.fill"
        case .backup: return "externaldrive.fill.badge.timemachine"
        case .other: return "doc.fill"
        }
    }

    var accent: Color {
        switch self {
        case .video: return .pink
        case .archive: return .orange
        case .diskImage: return .purple
        case .installer: return .indigo
        case .document: return .blue
        case .backup: return .teal
        case .other: return .gray
        }
    }

    /// Classify by case-insensitive file extension. Falls back to `.other`.
    static func classify(extension ext: String) -> LargeFileKind {
        let e = ext.lowercased()
        switch e {
        case "mov", "mp4", "mkv", "avi", "m4v", "webm", "wmv", "flv":
            return .video
        case "zip", "tar", "gz", "tgz", "7z", "rar", "bz2", "xz":
            return .archive
        case "dmg", "iso", "img", "cdr":
            return .diskImage
        case "pkg", "mpkg":
            return .installer
        case "pdf", "psd", "sketch", "fig", "key", "numbers", "pages", "ai", "indd":
            return .document
        case "sparsebundle", "ipsw", "backup", "bak":
            return .backup
        default:
            return .other
        }
    }
}

/// One large file, surfaced by `LargeFileFinder`. Identified by `id` so multi-select
/// in a SwiftUI `List` works without resorting to the URL (URLs may not be Hashable
/// in a stable way across rescans).
struct LargeFile: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let size: Int64
    let modifiedDate: Date?
    let kind: LargeFileKind

    init(url: URL, size: Int64, modifiedDate: Date?, kind: LargeFileKind) {
        self.id = UUID()
        self.url = url
        self.size = size
        self.modifiedDate = modifiedDate
        self.kind = kind
    }

    var displayName: String { url.lastPathComponent }

    /// Path with the filename stripped, for the secondary line under the file name.
    var displayDirectory: String {
        let parent = url.deletingLastPathComponent().path
        let home = NSHomeDirectory()
        if parent.hasPrefix(home) {
            return "~" + String(parent.dropFirst(home.count))
        }
        return parent
    }

    /// "2 weeks ago" / "yesterday" — used in the trailing column.
    var relativeModified: String? {
        guard let date = modifiedDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
