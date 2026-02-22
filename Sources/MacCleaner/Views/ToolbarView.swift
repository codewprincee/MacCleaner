import SwiftUI

struct ToolbarView: View {
    @ObservedObject var viewModel: CleanupViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Select all
            Button {
                viewModel.toggleSelectAll()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: viewModel.allSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(viewModel.allSelected ? .blue : .secondary)
                    Text(viewModel.allSelected ? "Deselect All" : "Select All")
                        .font(.subheadline)
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isScanning || viewModel.isCleaning)

            Spacer()

            // Total selected size badge
            if viewModel.totalSelectedSize > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "externaldrive.fill")
                        .font(.caption2)
                    Text(ByteFormatter.format(viewModel.totalSelectedSize))
                        .font(.system(.subheadline, design: .monospaced, weight: .medium))
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.blue.opacity(0.1))
                .clipShape(Capsule())
            }

            // Rescan
            Button {
                Task { await viewModel.scanAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(viewModel.isScanning || viewModel.isCleaning)
            .help("Rescan all categories")

            // Clean selected
            Button {
                Task { await viewModel.cleanSelected() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Clean Selected")
                        .font(.system(.body, weight: .semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.regular)
            .disabled(!viewModel.hasSelectedCategories || viewModel.isScanning || viewModel.isCleaning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
