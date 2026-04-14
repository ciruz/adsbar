import SwiftUI

struct FeederRowView: View {
    let feeder: Feeder
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onOpenFeedStatus: () -> Void
    let onOpenWebUI: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggleExpand) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(feeder.isOnline ? Color.green : Color.red)
                        .frame(width: 8, height: 8)

                    Text(feeder.device.name)
                        .font(.system(.body, weight: .medium))
                        .lineLimit(1)

                    Spacer()

                    if feeder.isOnline, let info = feeder.info {
                        Text("\(info.aircraftTracked ?? 0) AC")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)

                        if let mps = info.tar1090?.messagesPerSec {
                            Text(String(format: "%.0f/s", mps))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(info.aircraftADSB ?? 0) ADS-B")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        if let sig = info.tar1090?.signal {
                            Text(String(format: "%.1f dBFS", sig))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(signalColor(sig))
                        } else if let status = info.feedStatus {
                            Text(status)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(status == "connected" ? Color(red: 0.2, green: 0.6, blue: 0.3) : .orange)
                        }
                    } else {
                        Text("offline")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)

            if isExpanded {
                DetailView(
                    feeder: feeder,
                    onOpenFeedStatus: onOpenFeedStatus,
                    onOpenWebUI: onOpenWebUI,
                    onEdit: onEdit,
                    onDelete: onDelete
                )
            }
        }
    }

    private func signalColor(_ dB: Double) -> Color {
        if dB > -3 { return .red }
        if dB > -20 { return Color(red: 0.2, green: 0.6, blue: 0.3) }
        if dB > -35 { return .orange }
        return .red
    }
}

private struct DetailView: View {
    let feeder: Feeder
    let onOpenFeedStatus: () -> Void
    let onOpenWebUI: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if feeder.isOnline, let info = feeder.info {
                let fields = buildFields(info: info, ip: feeder.device.ip, port: feeder.device.port, type: feeder.device.stationType)
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], alignment: .leading, spacing: 6) {
                    ForEach(fields, id: \.label) { field in
                        DetailField(label: field.label, value: field.value)
                    }
                }
            } else {
                Text("Station is offline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DetailField(label: "Host", value: "\(feeder.device.ip):\(feeder.device.port)")
            }

            Divider()

            HStack(spacing: 8) {
                if feeder.device.stationType == .fr24 {
                    Button(action: onOpenFeedStatus) {
                        Label("Feed Status", systemImage: "airplane")
                            .font(.caption)
                    }
                } else if feeder.device.stationType == .readsb {
                    Button(action: onOpenFeedStatus) {
                        Label("Map", systemImage: "map")
                            .font(.caption)
                    }
                }

                Button(action: onOpenWebUI) {
                    Label("Web UI", systemImage: "safari")
                        .font(.caption)
                }

                Spacer()

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption)
                }

                Button(role: .destructive, action: onDelete) {
                    Label("Remove", systemImage: "trash")
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .padding(.top, 4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func buildFields(info: FeederInfo, ip: String, port: Int, type: StationType) -> [(label: String, value: String)] {
        var fields: [(label: String, value: String)] = []

        fields.append(("Host", "\(ip):\(port)"))
        fields.append(("Type", type.displayName))
        if let alias = info.feedAlias { fields.append(("Alias", alias)) }

        fields.append(("Aircraft", "\(info.aircraftTracked ?? 0)"))
        if let adsb = info.aircraftADSB { fields.append(("ADS-B", "\(adsb)")) }
        if let nonAdsb = info.aircraftNonADSB { fields.append(("Non-ADSB", "\(nonAdsb)")) }
        if info.totalMessages != nil { fields.append(("Messages", info.formattedMessages)) }

        if let t = info.tar1090 {
            if let mps = t.messagesPerSec { fields.append(("Msgs/sec", String(format: "%.0f", mps))) }
            if let pos = t.positionsPerSec { fields.append(("Pos/sec", String(format: "%.1f", pos))) }
            if let sig = t.signal { fields.append(("Signal", String(format: "%.1f dBFS", sig))) }
            if let noise = t.noise { fields.append(("Noise", String(format: "%.1f dBFS", noise))) }
            if let peak = t.peakSignal { fields.append(("Peak", String(format: "%.1f dBFS", peak))) }
            if let tracks = t.tracksTotal { fields.append(("Tracks", "\(tracks)")) }
        }

        if type == .fr24 {
            if let status = info.feedStatus { fields.append(("Feed", status)) }
            if let rx = info.receiverConnected {
                fields.append(("Receiver", rx ? "Connected" : "Disconnected"))
            }
            if let mlat = info.mlatStatus { fields.append(("MLAT", mlat)) }
            if let connected = info.lastConnected { fields.append(("Connected", connected)) }
            if let legacyId = info.feedLegacyId { fields.append(("Legacy ID", legacyId)) }
        }

        if let rangeKm = info.maxRangeKm {
            let unit = SettingsStore.shared.distanceUnit
            let converted = unit.convert(rangeKm)
            fields.append(("Max Range", String(format: "%.0f %@", converted, unit.label)))
        }

        if let lat = info.receiverLat, let lon = info.receiverLon {
            fields.append(("Location", String(format: "%.4f, %.4f", lat, lon)))
        }

        if let version = info.version { fields.append(("Version", version)) }
        if let build = info.buildRevision { fields.append(("Build", build)) }

        return fields
    }
}

private struct DetailField: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
