import Sparkle
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case notifications = "Notifications"
    case about = "About"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .notifications: return "bell"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    var settings = SettingsStore.shared
    var updater: SPUUpdater
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    TabButton(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsTab(settings: settings, updater: updater)
                case .notifications:
                    NotificationSettingsTab(settings: settings)
                case .about:
                    AboutSettingsTab()
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 360, height: 540)
    }
}

private struct TabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18))
                Text(tab.rawValue)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) :
                        isHovering ? Color.primary.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore
    var updater: SPUUpdater

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
            } header: {
                Text("Startup")
            }

            Section {
                Picker("Polling Interval", selection: $settings.pollingInterval) {
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                    Text("60 seconds").tag(60.0)
                }
                Picker("Distance Unit", selection: $settings.distanceUnit) {
                    ForEach(DistanceUnit.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
            } header: {
                Text("Monitoring")
            }

            Section {
                Toggle("Aircraft", isOn: $settings.showAircraftInBar)
                Toggle("Msgs/sec", isOn: $settings.showMsgsInBar)
                Toggle("Signal", isOn: $settings.showSignalInBar)
                Toggle("Max Range", isOn: $settings.showRangeInBar)
            } header: {
                Text("Status Bar")
            }
        }
        .formStyle(.grouped)
    }
}

struct NotificationSettingsTab: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Station Offline", isOn: $settings.notifyDeviceOffline)
            } header: {
                Text("Alerts")
            }

            Section {
                Button("Send Test Notification") {
                    NotificationService.shared.sendDeviceOffline(name: "Test Station")
                }
            } header: {
                Text("Test")
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutSettingsTab: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(spacing: 2) {
                Text("ADSBar")
                    .font(.title3.bold())

                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("ADS-B station monitoring, simplified.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}
