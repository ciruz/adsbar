import SwiftUI

struct SummaryView: View {
    let totalAircraft: Int
    let totalADSB: Int
    let totalMessages: Int
    let avgSignal: Double?
    let avgMsgsPerSec: Double?
    let onlineCount: Int
    let totalCount: Int

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("ADSBar")
                    .font(.headline)
                Spacer()
                Text("\(onlineCount)/\(totalCount) online")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                StatBadge(label: "Aircraft", value: "\(totalAircraft)")
                StatBadge(label: "ADS-B", value: "\(totalADSB)")
                StatBadge(
                    label: avgMsgsPerSec != nil ? "Msgs/sec" : "Messages",
                    value: avgMsgsPerSec != nil ? String(format: "%.0f", avgMsgsPerSec!) : formatTotalMessages(totalMessages)
                )
                StatBadge(label: "Signal", value: avgSignal != nil ? String(format: "%.1f dBFS", avgSignal!) : "-")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func formatTotalMessages(_ msgs: Int) -> String {
        if msgs >= 1_000_000 {
            return String(format: "%.1fM", Double(msgs) / 1_000_000)
        } else if msgs >= 1000 {
            return String(format: "%.1fK", Double(msgs) / 1000)
        } else {
            return "\(msgs)"
        }
    }
}

struct StatBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.body, design: .monospaced, weight: .semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
