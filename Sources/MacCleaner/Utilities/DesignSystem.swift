import SwiftUI

// MARK: - Theme & Design Tokens

enum Theme {
    // MARK: - Spacing (8-point grid)
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
        static let xxxxl: CGFloat = 64
    }

    // MARK: - Corner Radius (12pt minimum, 22pt maximum)
    enum Radius {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 14
        static let xl: CGFloat = 18
        static let xxl: CGFloat = 22
        static let pill: CGFloat = 999
    }

    // MARK: - Window
    enum Window {
        static let minWidth: CGFloat = 980
        static let minHeight: CGFloat = 680
        static let defaultWidth: CGFloat = 1180
        static let defaultHeight: CGFloat = 760
        static let sidebarMin: CGFloat = 220
        static let sidebarIdeal: CGFloat = 240
        static let sidebarMax: CGFloat = 280
    }

    // MARK: - Animation
    enum Motion {
        /// Emphatic, used for state-changing transitions (sheet, overlay, hero).
        static let snappy: Animation = .snappy(duration: 0.32, extraBounce: 0.12)
        /// Layout shifts, list reflows, donut updates.
        static let smooth: Animation = .smooth(duration: 0.25)
        /// Hover responses; should feel instant but not jarring.
        static let quick: Animation = .easeOut(duration: 0.16)
        /// Spring used for press states.
        static let press: Animation = .spring(response: 0.22, dampingFraction: 0.7)
        /// Used once per scan to animate the hero counter in.
        static let counter: Animation = .smooth(duration: 0.6)
    }

    // MARK: - Shadows
    enum Shadow {
        struct Style {
            let color: Color
            let radius: CGFloat
            let y: CGFloat
        }
        static let card = Style(color: .black.opacity(0.06), radius: 6, y: 2)
        static let cardHover = Style(color: .black.opacity(0.10), radius: 14, y: 6)
        static let modal = Style(color: .black.opacity(0.22), radius: 36, y: 14)
        static let glow = Style(color: .accentColor.opacity(0.45), radius: 16, y: 8)
        static let glowHover = Style(color: .accentColor.opacity(0.55), radius: 24, y: 10)
    }

    // MARK: - Typography
    enum Typography {
        /// Hero number on Smart Clean. 96pt rounded bold.
        static let hero = Font.system(size: 96, weight: .bold, design: .rounded)
        /// Secondary hero (for narrower windows or summary).
        static let heroCompact = Font.system(size: 64, weight: .bold, design: .rounded)
        /// Display number, e.g. summary "X.X GB freed".
        static let display = Font.system(size: 48, weight: .bold, design: .rounded)
        /// Section title, e.g. "Breakdown by Category".
        static let sectionTitle = Font.system(.title3, design: .rounded).weight(.semibold)
        /// Card title, e.g. "User Caches".
        static let cardTitle = Font.system(.body).weight(.medium)
        /// Eyebrow above hero number ("RECLAIMABLE SPACE").
        static let eyebrow = Font.system(.caption).weight(.semibold)
        /// Tabular number, used for byte counts in tables.
        static let tabular = Font.system(.callout, design: .rounded).weight(.medium)
    }
}

// MARK: - Group Definition (Sidebar grouping)

enum CategoryGroup: String, CaseIterable, Identifiable {
    case fileSystem = "File System"
    case xcode = "Xcode"
    case browsers = "Browsers"
    case packageManagers = "Package Managers"
    case system = "System"
    case containers = "Containers"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .fileSystem: return "folder.fill"
        case .xcode: return "hammer.fill"
        case .browsers: return "globe"
        case .packageManagers: return "shippingbox.fill"
        case .system: return "lock.shield.fill"
        case .containers: return "cube.box.fill"
        }
    }

    /// Per-group accent. Use these ONLY in the donut chart and the per-category
    /// detail header. Top-level chrome (hero, primary CTA) sticks to one accent.
    var accentColor: Color {
        switch self {
        case .fileSystem: return .blue
        case .xcode: return .indigo
        case .browsers: return .cyan
        case .packageManagers: return .orange
        case .system: return .red
        case .containers: return .teal
        }
    }

    var requiresAdmin: Bool { self == .system }

    var subtitle: String {
        switch self {
        case .fileSystem: return "Caches, logs, temp files, trash"
        case .xcode: return "Developer tools and simulators"
        case .browsers: return "Safari and Chrome cache"
        case .packageManagers: return "Homebrew, npm, pip, Yarn, CocoaPods"
        case .system: return "System-level cleanups"
        case .containers: return "Docker images and volumes"
        }
    }

    var types: [CleanupType] {
        switch self {
        case .fileSystem:
            return [
                .userCaches, .systemLogs, .tempFiles, .trash,
                .downloadsOldFiles, .mailDownloads, .iosBackups, .quicktimeRecordings,
            ]
        case .xcode:
            return [.xcodeDerivedData, .xcodeDeviceSupport, .xcodeSimulators, .xcodeArchives]
        case .browsers:
            return [
                .safariCache, .chromeCache, .braveCache, .arcCache,
                .edgeCache, .firefoxCache, .vivaldiCache, .operaCache,
            ]
        case .packageManagers:
            return [
                .homebrewCache, .npmCache, .pipCache, .yarnCache, .cocoapodsCache,
                .cargoCache, .goModuleCache, .condaCache, .bundlerCache,
                .gradleCache, .mavenCache, .composerCache,
            ]
        case .system:
            return [
                .systemCaches, .dnsCache,
                .diagnosticReports, .crashReporter, .timeMachineLocalSnapshots,
            ]
        case .containers:
            return [.dockerData]
        }
    }
}

extension CleanupType {
    var group: CategoryGroup {
        for group in CategoryGroup.allCases where group.types.contains(self) {
            return group
        }
        return .fileSystem
    }

    var accentColor: Color { group.accentColor }
}

// MARK: - Sidebar Selection

enum SidebarSelection: Hashable {
    case smartClean
    case appUninstaller
    case largeFiles
    case duplicates
    case group(CategoryGroup)
}

// MARK: - Brand Gradient

extension ShapeStyle where Self == LinearGradient {
    /// The single brand gradient used on the hero number and primary CTA.
    /// Blue -> cyan, respects light/dark mode via `.accentColor` system tint.
    static var brandHero: LinearGradient {
        LinearGradient(
            colors: [
                Color.accentColor,
                Color(nsColor: .systemTeal).opacity(0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var brandSubtle: LinearGradient {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.85),
                Color(nsColor: .systemTeal).opacity(0.85)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - View Modifiers

struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.Radius.lg
    var material: Material = .regularMaterial
    var stroke: Bool = true
    var solid: Bool = false  // used when reduceTransparency is on

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(solid
                          ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
                          : AnyShapeStyle(material))
            }
            .overlay {
                if stroke {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func cardBackground(
        radius: CGFloat = Theme.Radius.lg,
        material: Material = .regularMaterial,
        stroke: Bool = true,
        solid: Bool = false
    ) -> some View {
        modifier(CardBackground(radius: radius, material: material, stroke: stroke, solid: solid))
    }

    /// Card shadow that intensifies on hover. Pass the hover state.
    func liftOnHover(_ hovered: Bool, intensity: CGFloat = 1) -> some View {
        let style = hovered ? Theme.Shadow.cardHover : Theme.Shadow.card
        return self.shadow(
            color: style.color.opacity(intensity),
            radius: style.radius,
            y: style.y
        )
    }
}

// MARK: - Animated Counter (for hero number)

struct AnimatedByteText: View {
    let bytes: Int64
    var font: Font = .system(.largeTitle, design: .rounded).weight(.bold)
    var foreground: AnyShapeStyle = AnyShapeStyle(.primary)
    var kerning: CGFloat = 0

    @State private var displayed: Double = 0

    var body: some View {
        Text(formatted(Int64(displayed)))
            .font(font)
            .kerning(kerning)
            .foregroundStyle(foreground)
            .monospacedDigit()
            .contentTransition(.numericText())
            .onChange(of: bytes) { _, newValue in
                withAnimation(Theme.Motion.counter) {
                    displayed = Double(newValue)
                }
            }
            .onAppear {
                withAnimation(Theme.Motion.counter) {
                    displayed = Double(bytes)
                }
            }
            .accessibilityLabel(accessibleByteString(bytes))
    }

    private func formatted(_ b: Int64) -> String {
        ByteFormatter.format(b)
    }

    private func accessibleByteString(_ b: Int64) -> String {
        // VoiceOver-friendly. "12.4 gigabytes" instead of "12.4 GB".
        let raw = ByteFormatter.format(b)
        return raw
            .replacingOccurrences(of: " B", with: " bytes")
            .replacingOccurrences(of: " KB", with: " kilobytes")
            .replacingOccurrences(of: " MB", with: " megabytes")
            .replacingOccurrences(of: " GB", with: " gigabytes")
            .replacingOccurrences(of: " TB", with: " terabytes")
    }
}

// MARK: - Shimmer Placeholder

struct ShimmerPlaceholder: View {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat = Theme.Radius.md

    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.quaternary.opacity(0.5))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white.opacity(0.35), location: 0.5),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: UnitPoint(x: phase, y: 0.5),
                            endPoint: UnitPoint(x: phase + 1, y: 0.5)
                        )
                    )
                    .blendMode(.plusLighter)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 2
                }
            }
    }
}

// MARK: - Helpers on CleanupViewModel

extension CleanupViewModel {
    func categories(in group: CategoryGroup) -> [CleanupCategory] {
        let order = group.types
        return categories
            .filter { order.contains($0.type) }
            .sorted { lhs, rhs in
                guard let l = order.firstIndex(of: lhs.type),
                      let r = order.firstIndex(of: rhs.type) else { return false }
                return l < r
            }
    }

    func reclaimable(in group: CategoryGroup) -> Int64 {
        categories(in: group)
            .filter(\.isAvailable)
            .reduce(0) { $0 + $1.estimatedSize }
    }

    var totalReclaimable: Int64 {
        categories
            .filter(\.isAvailable)
            .reduce(0) { $0 + $1.estimatedSize }
    }

    /// The single largest available item — used in the hero stat strip.
    var largestItem: CleanupCategory? {
        categories
            .filter { $0.isAvailable && $0.estimatedSize > 0 }
            .max { $0.estimatedSize < $1.estimatedSize }
    }

    /// Number of distinct categories with reclaimable space.
    var reclaimableCategoryCount: Int {
        categories.filter { $0.isAvailable && $0.estimatedSize > 0 }.count
    }

    /// Number of selected available categories.
    var selectedCount: Int {
        categories.filter { $0.isSelected && $0.isAvailable }.count
    }
}
