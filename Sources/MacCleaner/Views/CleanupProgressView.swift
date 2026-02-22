import SwiftUI

struct CleanupProgressView: View {
    let progress: Double
    let currentCategory: String

    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: 24) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.1))
                    .frame(width: 72, height: 72)

                Image(systemName: "sparkles")
                    .font(.system(size: 30))
                    .foregroundStyle(.blue)
            }

            VStack(spacing: 6) {
                Text("Cleaning in Progress")
                    .font(.title3.weight(.semibold))

                Text(currentCategory)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Progress bar
            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .frame(width: 280)

                Text(String(format: "%.0f%%", progress * 100))
                    .font(.system(.callout, design: .monospaced, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 36)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 30, y: 10)
    }
}
