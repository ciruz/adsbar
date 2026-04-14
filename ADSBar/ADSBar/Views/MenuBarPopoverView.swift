import Sparkle
import SwiftUI

struct MenuBarPopoverView: View {
    var store: FeederStore
    var updater: SPUUpdater

    var body: some View {
        VStack(spacing: 0) {
            SummaryView(
                totalAircraft: store.totalAircraft,
                totalADSB: store.totalADSB,
                totalMessages: store.totalMessages,
                avgSignal: store.avgSignal,
                avgMsgsPerSec: store.avgMsgsPerSec,
                onlineCount: store.onlineCount,
                totalCount: store.feeders.count
            )
            .frame(height: 80)

            Divider()

            scanStatusBar

            ScrollView {
                VStack(spacing: 0) {
                    if store.feeders.isEmpty, !store.isScanning, store.scanStatus.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No stations configured")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Add a station or scan your network")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }

                    ForEach(store.feeders) { feeder in
                        FeederRowView(
                            feeder: feeder,
                            isExpanded: store.expandedDeviceID == feeder.id,
                            onToggleExpand: { store.toggleExpanded(feeder.id) },
                            onOpenFeedStatus: { store.openFeedStatus(feeder) },
                            onOpenWebUI: { store.openWebUI(feeder.device) },
                            onEdit: { store.beginEdit(feeder.device) },
                            onDelete: { store.removeDevice(feeder) }
                        )
                        Divider()
                    }
                }
            }
            .frame(minHeight: 200, maxHeight: 700)

            Divider()
                .opacity(store.editingDevice != nil ? 1 : 0)
                .frame(height: store.editingDevice != nil ? nil : 0)
            EditDeviceView(store: store)
                .frame(height: store.editingDevice != nil ? nil : 0)
                .clipped()
                .opacity(store.editingDevice != nil ? 1 : 0)

            Divider()
                .opacity(store.isAddingDevice ? 1 : 0)
                .frame(height: store.isAddingDevice ? nil : 0)
            AddDeviceView(store: store)
                .frame(height: store.isAddingDevice ? nil : 0)
                .clipped()
                .opacity(store.isAddingDevice ? 1 : 0)

            Divider()

            VStack(spacing: 1) {
                MenuFooterButton(title: "Add Station...", icon: "plus") {
                    store.isAddingDevice.toggle()
                }

                MenuFooterButton(title: "Scan Network", icon: "antenna.radiowaves.left.and.right") {
                    store.rescan()
                }

                Divider()
                    .padding(.vertical, 2)

                MenuFooterButton(title: "Settings...", icon: "gearshape") {
                    WindowManager.shared.openSettings()
                }

                MenuFooterButton(title: "Check for Updates...", icon: "arrow.triangle.2.circlepath") {
                    updater.checkForUpdates()
                }

                Divider()
                    .padding(.vertical, 2)

                MenuFooterButton(title: "Quit", icon: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 440)
        .background(PopoverMaterial())
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var scanStatusBar: some View {
        HStack(spacing: 6) {
            if store.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
            Text(store.scanStatus)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, store.scanStatus.isEmpty ? 0 : 6)
        .frame(height: store.scanStatus.isEmpty ? 0 : nil)
        .clipped()
    }
}

private struct PopoverMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct MenuFooterButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(title)
                Spacer()
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isHovering ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .padding(.horizontal, 4)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
