import SwiftUI

struct CleanupSummaryView: View {
    let summary: CleanupSummary
    let onDismiss: () -> Void
    @State private var showErrorDetails = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with gradient background
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(headerColor.opacity(0.15))
                        .frame(width: 72, height: 72)

                    Image(systemName: headerIcon)
                        .font(.system(size: 36))
                        .foregroundStyle(headerColor)
                }

                Text("Cleanup Complete")
                    .font(.title2.weight(.semibold))

                // Total freed
                VStack(spacing: 2) {
                    Text(ByteFormatter.format(summary.totalBytesFreed))
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(headerColor)
                    Text("space freed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 20)

            Divider().padding(.horizontal, 20)

            // Per-category results
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(summary.results) { result in
                        HStack(spacing: 10) {
                            Image(systemName: resultIcon(for: result))
                                .font(.system(size: 14))
                                .foregroundStyle(resultColor(for: result))
                                .frame(width: 20)

                            Text(result.type.rawValue)
                                .font(.system(.callout, weight: .medium))
                                .lineLimit(1)

                            Spacer()

                            if result.success || result.partialSuccess {
                                Text(ByteFormatter.format(result.bytesFreed))
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Failed")
                                    .font(.callout)
                                    .foregroundStyle(.red)
                            }

                            if !result.errors.isEmpty {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary.opacity(0.3))
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 20)
            }
            .frame(maxHeight: 220)
            .padding(.top, 16)

            // Error details
            if totalErrors > 0 {
                Button {
                    showErrorDetails = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                        Text("\(totalErrors) item(s) had errors")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }

            // Disk free after
            if let diskAfter = summary.diskAfter {
                HStack(spacing: 6) {
                    Image(systemName: "internaldrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Disk free:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(ByteFormatter.format(diskAfter.freeSpace))
                        .font(.system(.subheadline, design: .monospaced, weight: .medium))
                }
                .padding(.top, 14)
            }

            // Done button
            Button {
                onDismiss()
            } label: {
                Text("Done")
                    .font(.system(.body, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .frame(width: 420)
        .sheet(isPresented: $showErrorDetails) {
            ErrorDetailsView(summary: summary)
        }
        .onAppear { appeared = true }
    }

    private var headerIcon: String {
        if summary.failureCount == 0 { return "checkmark.circle.fill" }
        else if summary.successCount > 0 { return "exclamationmark.triangle.fill" }
        else { return "xmark.circle.fill" }
    }

    private var headerColor: Color {
        if summary.failureCount == 0 { return .green }
        else if summary.successCount > 0 { return .orange }
        else { return .red }
    }

    private var totalErrors: Int {
        summary.results.reduce(0) { $0 + $1.errors.count }
    }

    private func resultIcon(for result: CleanupResult) -> String {
        if result.success { return "checkmark.circle.fill" }
        if result.partialSuccess { return "exclamationmark.circle.fill" }
        return "xmark.circle.fill"
    }

    private func resultColor(for result: CleanupResult) -> Color {
        if result.success { return .green }
        if result.partialSuccess { return .orange }
        return .red
    }
}

struct ErrorDetailsView: View {
    let summary: CleanupSummary
    @Environment(\.dismiss) var dismiss

    var errorGroups: [(type: CleanupType, errors: [FileCleanupError])] {
        summary.results
            .filter { !$0.errors.isEmpty }
            .map { (type: $0.type, errors: $0.errors) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Cleanup Errors")
                    .font(.title3.weight(.semibold))
                Spacer()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(errorGroups, id: \.type.id) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.type.rawValue)
                                .font(.system(.callout, weight: .semibold))

                            ForEach(item.errors) { error in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.red.opacity(0.7))
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(error.path)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.primary)
                                        Text(error.reason)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 400)
    }
}
