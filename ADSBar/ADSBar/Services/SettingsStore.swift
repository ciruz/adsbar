import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLoginItem()
        }
    }

    var pollingInterval: Double {
        didSet { UserDefaults.standard.set(pollingInterval, forKey: "pollingInterval") }
    }

    // MARK: - Notification Settings

    var notifyDeviceOffline: Bool {
        didSet { UserDefaults.standard.set(notifyDeviceOffline, forKey: "notifyDeviceOffline") }
    }

    var distanceUnit: DistanceUnit {
        didSet { UserDefaults.standard.set(distanceUnit.rawValue, forKey: "distanceUnit") }
    }

    var showAircraftInBar: Bool {
        didSet { UserDefaults.standard.set(showAircraftInBar, forKey: "showAircraftInBar") }
    }

    var showMsgsInBar: Bool {
        didSet { UserDefaults.standard.set(showMsgsInBar, forKey: "showMsgsInBar") }
    }

    var showSignalInBar: Bool {
        didSet { UserDefaults.standard.set(showSignalInBar, forKey: "showSignalInBar") }
    }

    var showRangeInBar: Bool {
        didSet { UserDefaults.standard.set(showRangeInBar, forKey: "showRangeInBar") }
    }

    private init() {
        UserDefaults.standard.register(defaults: [
            "launchAtLogin": false,
            "pollingInterval": 10.0,
            "notifyDeviceOffline": true,
            "distanceUnit": DistanceUnit.km.rawValue,
            "showAircraftInBar": true,
            "showMsgsInBar": true,
            "showSignalInBar": true,
            "showRangeInBar": false
        ])
        launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        pollingInterval = UserDefaults.standard.double(forKey: "pollingInterval")
        notifyDeviceOffline = UserDefaults.standard.bool(forKey: "notifyDeviceOffline")
        distanceUnit = DistanceUnit(rawValue: UserDefaults.standard.string(forKey: "distanceUnit") ?? "km") ?? .km
        showAircraftInBar = UserDefaults.standard.bool(forKey: "showAircraftInBar")
        showMsgsInBar = UserDefaults.standard.bool(forKey: "showMsgsInBar")
        showSignalInBar = UserDefaults.standard.bool(forKey: "showSignalInBar")
        showRangeInBar = UserDefaults.standard.bool(forKey: "showRangeInBar")
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Login item error: \(error)")
        }
    }
}
