import SwiftUI

struct CleanupSummaryView: View {
    let summary: CleanupSummary
    let onDismiss: () -> Void
    @State private var showErrorDetails = false

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Image(systemName: headerIcon)
                .font(.system(size: 48))
                .foregroundStyle(headerColor)

            Text("Cleanup Complete")
                .font(.title2.weight(.semibold))

            // Total freed
            VStack(spacing: 4) {
                Text(ByteFormatter.format(summary.totalBytesFreed))
                    .font(.system(.title, design: .monospaced).weight(.bold))
                    .foregroundStyle(.blue)
                Text("total space freed")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Per-category results
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(summary.results) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: resultIcon(for: result))
                                    .foregroundStyle(resultColor(for: result))
                                    .font(.caption)

                                Text(result.type.rawValue)
                                    .font(.body)

                                Spacer()

                                if result.success || result.partialSuccess {
                                    Text(ByteFormatter.format(result.bytesFreed))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Failed")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }

                            if !result.errors.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                    Text("\(result.errors.count) file(s) could not be removed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.leading, 20)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxHeight: 200)

            // Error details button
            if totalErrors > 0 {
                Button("View \(totalErrors) Error(s)") {
                    showErrorDetails = true
                }
                .font(.caption)
                .buttonStyle(.link)
            }

            // Summary stats
            if summary.failureCount > 0 {
                HStack {
                    Label("\(summary.successCount) succeeded", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("/")
                        .foregroundStyle(.secondary)
                    Label("\(summary.failureCount) failed", systemImage: "xmark.circle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            // Disk usage after
            if let diskAfter = summary.diskAfter {
                Divider()
                HStack {
                    Text("Disk free:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(ByteFormatter.format(diskAfter.freeSpace))
                        .font(.system(.subheadline, design: .monospaced).weight(.medium))
                }
            }

            Button("Done") {
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
        .padding(30)
        .frame(width: 450)
        .sheet(isPresented: $showErrorDetails) {
            ErrorDetailsView(summary: summary)
        }
    }

    private var headerIcon: String {
        if summary.failureCount == 0 {
            return "checkmark.circle.fill"
        } else if summary.successCount > 0 {
            return "exclamationmark.triangle.fill"
        } else {
            return "xmark.circle.fill"
        }
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
            Text("Cleanup Errors")
                .font(.title2.weight(.semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(errorGroups, id: \.type.id) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.type.rawValue)
                                .font(.headline)

                            ForEach(item.errors) { error in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(error.path)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text(error.reason)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 550, height: 400)
    }
}
