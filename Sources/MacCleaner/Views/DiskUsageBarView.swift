import SwiftUI

struct DiskUsageBarView: View {
    let diskUsage: DiskUsageInfo?

    var body: some View {
        VStack(spacing: 0) {
            if let disk = diskUsage {
                HStack(alignment: .top) {
                    // Left: icon + title
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "internaldrive")
                                .font(.system(size: 28))
                                .foregroundStyle(.blue)
                                .symbolRenderingMode(.hierarchical)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Macintosh HD")
                                    .font(.headline)
                                Text("\(ByteFormatter.format(disk.freeSpace)) available")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    // Right: capacity
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(ByteFormatter.format(disk.totalSpace))
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                        Text("total capacity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.quaternary)

                        RoundedRectangle(cornerRadius: 5)
                            .fill(
                                LinearGradient(
                                    colors: barGradient(for: disk.usedPercentage),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * min(disk.usedPercentage, 1.0))
                    }
                }
                .frame(height: 10)
                .padding(.top, 12)

                HStack {
                    Label(ByteFormatter.format(disk.usedSpace), systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(ColorDotLabel(color: barPrimaryColor(for: disk.usedPercentage)))
                    Text("Used")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Text(String(format: "%.1f%% used", disk.usedPercentage * 100))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)

            } else {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning disk...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
    }

    private func barGradient(for percentage: Double) -> [Color] {
        if percentage > 0.9 {
            return [.red, .red.opacity(0.8)]
        } else if percentage > 0.75 {
            return [.orange, .red.opacity(0.7)]
        } else {
            return [.blue, .cyan]
        }
    }

    private func barPrimaryColor(for percentage: Double) -> Color {
        if percentage > 0.9 { return .red }
        else if percentage > 0.75 { return .orange }
        else { return .blue }
    }
}

struct ColorDotLabel: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            configuration.title
        }
    }
}
