import SwiftUI

struct CategoryRowView: View {
    @ObservedObject var category: CleanupCategory
    let onClean: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $category.isSelected) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .disabled(!category.isAvailable)

            ZStack(alignment: .bottomTrailing) {
                Image(systemName: category.type.icon)
                    .font(.title2)
                    .foregroundStyle(category.isAvailable ? .primary : .tertiary)
                    .frame(width: 28)

                if category.type.requiresElevation {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .offset(x: 4, y: 4)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(category.type.rawValue)
                        .font(.body)
                        .foregroundStyle(category.isAvailable ? .primary : .secondary)

                    if category.type.requiresElevation {
                        Image(systemName: "key.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("Requires administrator password")
                    }
                }

                Text(category.isAvailable
                     ? category.type.description
                     : (category.unavailableReason ?? "Not available"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if category.isScanning {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 60, alignment: .trailing)
            } else if category.isCleaning {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Cleaning...")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if category.isAvailable {
                Text(ByteFormatter.format(category.estimatedSize))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(category.estimatedSize > 0 ? .primary : .secondary)
                    .frame(minWidth: 80, alignment: .trailing)

                Button(action: onClean) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(category.estimatedSize == 0 && category.type != .dnsCache)
                .help("Clean \(category.type.rawValue)")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .opacity(category.isAvailable ? 1.0 : 0.6)
    }
}
