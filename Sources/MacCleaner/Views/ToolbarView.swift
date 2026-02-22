import SwiftUI

struct ToolbarView: View {
    @ObservedObject var viewModel: CleanupViewModel

    var body: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.toggleSelectAll()
            } label: {
                Label(
                    viewModel.allSelected ? "Deselect All" : "Select All",
                    systemImage: viewModel.allSelected ? "checkmark.circle.fill" : "circle"
                )
            }
            .disabled(viewModel.isScanning || viewModel.isCleaning)

            Spacer()

            // Total selected size
            if viewModel.totalSelectedSize > 0 {
                Text("Selected: \(ByteFormatter.format(viewModel.totalSelectedSize))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await viewModel.scanAll() }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isScanning || viewModel.isCleaning)

            Button {
                Task { await viewModel.cleanSelected() }
            } label: {
                Label("Clean Selected", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!viewModel.hasSelectedCategories || viewModel.isScanning || viewModel.isCleaning)
        }
        .padding()
    }
}
