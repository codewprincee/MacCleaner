import SwiftUI

struct DiskUsageBarView: View {
    let diskUsage: DiskUsageInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let disk = diskUsage {
                HStack {
                    Text("Disk Usage")
                        .font(.headline)
                    Spacer()
                    Text("\(ByteFormatter.format(disk.usedSpace)) used of \(ByteFormatter.format(disk.totalSpace))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.2))

                        RoundedRectangle(cornerRadius: 6)
                            .fill(barColor(for: disk.usedPercentage))
                            .frame(width: geometry.size.width * min(disk.usedPercentage, 1.0))
                    }
                }
                .frame(height: 12)

                HStack {
                    Text("\(ByteFormatter.format(disk.freeSpace)) free")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f%% used", disk.usedPercentage * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading disk info...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func barColor(for percentage: Double) -> Color {
        if percentage > 0.9 {
            return .red
        } else if percentage > 0.75 {
            return .orange
        } else {
            return .blue
        }
    }
}
