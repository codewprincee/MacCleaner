import SwiftUI

/// Full-screen cleanup progress overlay. Replaces the entire window with a
/// thick-material blur, an animated angular ring, the current category name,
/// and a Cancel button that flips the cooperative cancel flag in the VM.
struct CleanupProgressView: View {
    let progress: Double
    let currentCategory: String
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var pulse = false
    @State private var ringRotation: Double = 0
    @Namespace private var ringNamespace

    var body: some View {
        ZStack {
            // Frosted backdrop covering the full window.
            Group {
                if reduceTransparency {
                    Color(nsColor: .windowBackgroundColor)
                } else {
                    Rectangle().fill(.thickMaterial)
                }
            }
            .ignoresSafeArea()
            .overlay(Color.black.opacity(0.05).ignoresSafeArea())

            // Decorative sparkle particles — disabled if reduce-motion is on.
            if !reduceMotion && !reduceTransparency {
                SparkleField()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Center stack.
            VStack(spacing: Theme.Spacing.xl) {
                ringSection

                VStack(spacing: 6) {
                    Text("Cleaning \(currentCategory.isEmpty ? "…" : currentCategory)")
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .id(currentCategory)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))

                    Text(stepLabel)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .animation(Theme.Motion.smooth, value: currentCategory)

                progressBar

                Button(role: .cancel) {
                    onCancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .font(.system(.callout).weight(.medium))
                        .frame(minWidth: 110)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .padding(.top, Theme.Spacing.sm)
                .accessibilityLabel("Cancel cleanup")
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, Theme.Spacing.xxxl)
            .padding(.vertical, Theme.Spacing.xxl + Theme.Spacing.sm)
        }
        .onAppear {
            pulse = true
            if !reduceMotion {
                withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                    ringRotation = 360
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cleanup in progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }

    // MARK: - Ring section (200pt circle)

    private var ringSection: some View {
        ZStack {
            // Soft halo
            if !reduceTransparency {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 240, height: 240)
                    .blur(radius: 30)
            }

            // Background track
            Circle()
                .stroke(.quaternary.opacity(0.5), lineWidth: 8)
                .frame(width: 200, height: 200)

            // Progress arc with angular gradient
            Circle()
                .trim(from: 0, to: max(progress, 0.001))
                .stroke(
                    AngularGradient(
                        colors: [
                            .accentColor,
                            Color(nsColor: .systemTeal),
                            .accentColor
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-90 + (reduceMotion ? 0 : ringRotation * 0.25)))
                .animation(Theme.Motion.smooth, value: progress)

            // Center icon
            Image(systemName: "sparkles")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.brandHero)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(
                    .pulse,
                    options: reduceMotion ? .nonRepeating : .repeating,
                    isActive: !reduceMotion
                )
                .scaleEffect(pulse && !reduceMotion ? 1.05 : 1.0)
                .animation(
                    reduceMotion
                        ? .default
                        : .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                    value: pulse
                )
                .matchedGeometryEffect(id: "icon-\(currentCategory)", in: ringNamespace)
        }
    }

    private var progressBar: some View {
        VStack(spacing: 6) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .frame(width: 320)
                .clipShape(Capsule())

            Text(String(format: "%.0f%% complete", progress * 100))
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
        }
    }

    private var stepLabel: String {
        if progress <= 0 { return "Preparing…" }
        return "\(Int(progress * 100))% complete"
    }
}

// MARK: - Sparkle Field (Canvas)

private struct SparkleField: View {
    private struct Sparkle {
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var speed: CGFloat
        var phase: CGFloat
    }

    @State private var sparkles: [Sparkle] = (0..<60).map { _ in
        Sparkle(
            x: CGFloat.random(in: 0...1),
            y: CGFloat.random(in: 0...1),
            size: CGFloat.random(in: 1.5...3.5),
            speed: CGFloat.random(in: 0.04...0.16),
            phase: CGFloat.random(in: 0...1)
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for sparkle in sparkles {
                    let phase = (CGFloat(t) * sparkle.speed + sparkle.phase).truncatingRemainder(dividingBy: 1)
                    let y = (sparkle.y - phase + 1).truncatingRemainder(dividingBy: 1)
                    let twinkle = (sin((CGFloat(t) + sparkle.phase * 6) * 2.4) + 1) / 2
                    let opacity = 0.20 + twinkle * 0.45

                    let rect = CGRect(
                        x: sparkle.x * size.width - sparkle.size / 2,
                        y: y * size.height - sparkle.size / 2,
                        width: sparkle.size,
                        height: sparkle.size
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(opacity))
                    )
                }
            }
        }
    }
}
