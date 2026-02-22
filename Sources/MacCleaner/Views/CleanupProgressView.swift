import SwiftUI

struct CleanupProgressView: View {
    let progress: Double
    let currentCategory: String

    var body: some View {
        VStack(spacing: 20) {
            Text("Cleaning in Progress")
                .font(.title2.weight(.semibold))

            ProgressView(value: progress) {
                Text("Cleaning \(currentCategory)...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .progressViewStyle(.linear)
            .frame(width: 300)

            Text(String(format: "%.0f%%", progress * 100))
                .font(.system(.title, design: .monospaced))
                .foregroundStyle(.blue)
        }
        .padding(40)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
    }
}
