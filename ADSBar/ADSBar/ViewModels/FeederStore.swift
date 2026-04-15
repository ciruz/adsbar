import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class FeederStore {
    var feeders: [Feeder] = []
    var isAddingDevice = false
    var newDeviceName = ""
    var newDeviceIP = ""
    var newDevicePort = "8754"
    var newDeviceType: StationType = .fr24
    var expandedDeviceID: String?
    var editingDevice: DeviceConfig?
    var editName = ""
    var editIP = ""
    var editPort = "8754"
    var editType: StationType = .fr24
    var newDeviceWebPath = ""
    var newDeviceLat = ""
    var newDeviceLon = ""
    var newDeviceSSL = false
    var editWebPath = ""
    var editLat = ""
    var editLon = ""
    var editSSL = false

    private let feederAPI = FeederAPIService()
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    private let scanner = NetworkScanner()
    private let settings = SettingsStore.shared
    private let notifications = NotificationService.shared
    @ObservationIgnored private var previousStates: [String: FeederSnapshot] = [:]
    @ObservationIgnored private var hasCompletedFirstPoll = false

    private struct FeederSnapshot {
        let isOnline: Bool
    }

    var totalAircraft: Int {
        feeders.filter(\.isOnline).compactMap(\.info?.aircraftTracked).reduce(0, +)
    }

    var totalADSB: Int {
        feeders.filter(\.isOnline).compactMap(\.info?.aircraftADSB).reduce(0, +)
    }

    var totalMessages: Int {
        feeders.filter(\.isOnline).compactMap(\.info?.totalMessages).reduce(0, +)
    }

    var avgSignal: Double? {
        let signals = feeders.filter(\.isOnline).compactMap(\.info?.tar1090?.signal)
        guard !signals.isEmpty else { return nil }
        return signals.reduce(0, +) / Double(signals.count)
    }

    var avgMsgsPerSec: Double? {
        let rates = feeders.filter(\.isOnline).compactMap(\.info?.tar1090?.messagesPerSec)
        guard !rates.isEmpty else { return nil }
        return rates.reduce(0, +)
    }

    var maxRange: Double? {
        let ranges = feeders.filter(\.isOnline).compactMap(\.info?.maxRangeKm)
        guard !ranges.isEmpty else { return nil }
        return ranges.max()
    }

    var onlineCount: Int {
        feeders.filter(\.isOnline).count
    }

    var menuBarTitle: String {
        guard !feeders.isEmpty else { return "✈  No Devices" }
        guard onlineCount > 0 else { return "✈  Offline" }
        var parts: [String] = []
        if settings.showAircraftInBar {
            parts.append("✈  \(totalAircraft)")
        }
        if settings.showMsgsInBar, let mps = avgMsgsPerSec {
            parts.append(String(format: "%.0f/s", mps))
        }
        if settings.showSignalInBar, let sig = avgSignal {
            parts.append(String(format: "%.1f dBFS", sig))
        }
        if settings.showRangeInBar, let rangeKm = maxRange {
            let unit = settings.distanceUnit
            parts.append(String(format: "%.0f %@", unit.convert(rangeKm), unit.label))
        }
        if parts.isEmpty { parts.append("✈") }
        return parts.joined(separator: " | ")
    }

    init() {
        let savedDevices = FeederStorage.load()
        feeders = savedDevices.map { device in
            Feeder(device: device)
        }
        startPolling()
    }

    func stop() {
        pollingTask?.cancel()
    }

    func addDevice() {
        let trimmedName = newDeviceName.trimmingCharacters(in: .whitespaces)
        let trimmedIP = newDeviceIP.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedIP.isEmpty else { return }

        let port = Int(newDevicePort) ?? newDeviceType.defaultPort
        let webPath = newDeviceWebPath.trimmingCharacters(in: .whitespaces)
        let lat = Double(newDeviceLat.trimmingCharacters(in: .whitespaces))
        let lon = Double(newDeviceLon.trimmingCharacters(in: .whitespaces))
        let device = DeviceConfig(
            name: trimmedName,
            ip: trimmedIP,
            port: port,
            stationType: newDeviceType,
            useSSL: newDeviceSSL,
            webUIPath: webPath.isEmpty ? nil : webPath,
            customLat: lat,
            customLon: lon
        )
        feeders.append(Feeder(device: device))
        saveDevices()
        newDeviceName = ""
        newDeviceIP = ""
        newDeviceType = .fr24
        newDevicePort = String(StationType.fr24.defaultPort)
        newDeviceWebPath = ""
        newDeviceLat = ""
        newDeviceLon = ""
        newDeviceSSL = false
        isAddingDevice = false

        let newID = device.id
        Task { await pollDevice(id: newID) }
    }

    func removeDevice(_ feeder: Feeder) {
        feeders.removeAll { $0.id == feeder.id }
        saveDevices()
    }

    func beginEdit(_ device: DeviceConfig) {
        editingDevice = device
        editName = device.name
        editIP = device.ip
        editPort = String(device.port)
        editType = device.stationType
        editWebPath = device.webUIPath ?? ""
        editLat = device.customLat != nil ? String(device.customLat!) : ""
        editLon = device.customLon != nil ? String(device.customLon!) : ""
        editSSL = device.useSSL
    }

    func saveEdit() {
        guard let editing = editingDevice else { return }
        if let index = feeders.firstIndex(where: { $0.device.id == editing.id }) {
            let webPath = editWebPath.trimmingCharacters(in: .whitespaces)
            let lat = Double(editLat.trimmingCharacters(in: .whitespaces))
            let lon = Double(editLon.trimmingCharacters(in: .whitespaces))
            let updatedDevice = DeviceConfig(
                id: editing.id,
                name: editName.trimmingCharacters(in: .whitespaces),
                ip: editIP.trimmingCharacters(in: .whitespaces),
                port: Int(editPort) ?? editType.defaultPort,
                stationType: editType,
                useSSL: editSSL,
                webUIPath: webPath.isEmpty ? nil : webPath,
                customLat: lat,
                customLon: lon
            )
            feeders[index] = Feeder(
                device: updatedDevice,
                info: feeders[index].info,
                isOnline: feeders[index].isOnline
            )
            saveDevices()
            Task { await pollDevice(id: editing.id) }
        }
        editingDevice = nil
    }

    func cancelEdit() {
        editingDevice = nil
    }

    func openFeedStatus(_ feeder: Feeder) {
        let url: URL?
        switch feeder.device.stationType {
        case .fr24:
            url = URL(string: "https://www.flightradar24.com/account/data-sharing")
        case .readsb:
            url = feeder.device.resolvedWebURL
        case .planefinder:
            url = feeder.device.resolvedWebURL
        case .airplanesLive:
            if let mapLink = feeder.info?.mapLink, !mapLink.isEmpty {
                url = URL(string: mapLink)
            } else {
                url = URL(string: "https://airplanes.live/myfeed/")
            }
        }
        if let url { NSWorkspace.shared.open(url) }
    }

    func openWebUI(_ device: DeviceConfig) {
        if device.stationType == .airplanesLive {
            // For airplanes.live, the map link comes from the API response
            if let feeder = feeders.first(where: { $0.device.id == device.id }),
               let mapLink = feeder.info?.mapLink, !mapLink.isEmpty,
               let url = URL(string: mapLink) {
                NSWorkspace.shared.open(url)
            } else if let url = URL(string: "https://globe.airplanes.live") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        if let url = device.resolvedWebURL {
            NSWorkspace.shared.open(url)
        }
    }

    func toggleExpanded(_ id: String) {
        if expandedDeviceID == id {
            expandedDeviceID = nil
        } else {
            expandedDeviceID = id
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                await pollAll()
                let interval = UInt64(settings.pollingInterval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func pollAll() async {
        guard !feeders.isEmpty else { return }
        let api = feederAPI
        let snapshot = feeders.map(\.device)
        await withTaskGroup(of: (String, FeederInfo?).self) { group in
            for device in snapshot {
                group.addTask {
                    let info = await api.fetchFeederInfo(device: device)
                    return (device.id, info)
                }
            }
            for await (deviceID, info) in group {
                guard let idx = feeders.firstIndex(where: { $0.device.id == deviceID }) else { continue }
                feeders[idx] = Feeder(device: feeders[idx].device, info: info, isOnline: info != nil)
            }
        }

        if hasCompletedFirstPoll {
            checkNotifications()
        }
        snapshotStates()
        hasCompletedFirstPoll = true
    }

    private func checkNotifications() {
        for feeder in feeders {
            let id = feeder.device.id
            let name = feeder.device.name
            guard let prev = previousStates[id] else { continue }

            if settings.notifyDeviceOffline, prev.isOnline, !feeder.isOnline {
                notifications.sendDeviceOffline(name: name)
            }
        }
    }

    private func snapshotStates() {
        previousStates = Dictionary(uniqueKeysWithValues: feeders.map { feeder in
            (feeder.device.id, FeederSnapshot(
                isOnline: feeder.isOnline
            ))
        })
    }

    private func pollDevice(id deviceID: String) async {
        guard let idx = feeders.firstIndex(where: { $0.device.id == deviceID }) else { return }
        let device = feeders[idx].device
        let info = await feederAPI.fetchFeederInfo(device: device)
        guard let newIdx = feeders.firstIndex(where: { $0.device.id == deviceID }) else { return }
        feeders[newIdx] = Feeder(device: feeders[newIdx].device, info: info, isOnline: info != nil)
    }

    private func saveDevices() {
        FeederStorage.save(feeders.map(\.device))
    }

    // MARK: - Network Scan

    var isScanning = false
    var scanStatus = ""

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var newlyFound = 0

    func rescan() {
        scanTask?.cancel()
        isScanning = true
        newlyFound = 0
        scanStatus = "Detecting local network..."

        guard let localIP = getLocalIPAddress() else {
            scanStatus = "Could not determine local IP"
            isScanning = false
            return
        }

        let subnet = localIP.split(separator: ".").dropLast().joined(separator: ".")
        scanStatus = "Scanning \(subnet).0/24..."

        scanTask = Task {
            await scanner.scan(
                localIP: localIP,
                onFound: { [weak self] device in
                    Task { @MainActor in
                        guard let self, !Task.isCancelled else { return }
                        guard !self.feeders.contains(where: { $0.device.ip == device.ip && $0.device.stationType == device.stationType }) else { return }
                        let config = DeviceConfig(name: device.hostname, ip: device.ip, port: device.port, stationType: device.stationType)
                        self.feeders.append(Feeder(device: config))
                        self.saveDevices()
                        self.newlyFound += 1
                        self.scanStatus = "Found \(self.newlyFound) new station\(self.newlyFound == 1 ? "" : "s")..."
                        let newDeviceID = config.id
                        Task { await self.pollDevice(id: newDeviceID) }
                    }
                },
                onProgress: { [weak self] checked, total in
                    Task { @MainActor in
                        guard let self, !Task.isCancelled else { return }
                        let pct = Int(Double(checked) / Double(total) * 100)
                        if self.newlyFound > 0 {
                            self.scanStatus = "Scanning... \(pct)% - \(self.newlyFound) new"
                        } else {
                            self.scanStatus = "Scanning... \(pct)%"
                        }
                    }
                }
            )
            if newlyFound > 0 {
                scanStatus = "Done - added \(newlyFound) station\(newlyFound == 1 ? "" : "s")"
            } else {
                scanStatus = feeders.isEmpty
                    ? "Done - no stations found"
                    : "Done - no new stations found"
            }
            isScanning = false
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !isScanning {
                scanStatus = ""
            }
        }
    }
}
