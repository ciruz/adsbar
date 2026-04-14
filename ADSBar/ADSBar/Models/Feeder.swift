import Foundation

enum StationType: String, Codable, CaseIterable, Identifiable {
    case fr24
    case readsb
    case planefinder

    var id: String {
        rawValue
    }

    var defaultPort: Int {
        switch self {
        case .fr24: return 8754
        case .readsb: return 8080
        case .planefinder: return 30053
        }
    }

    var displayName: String {
        switch self {
        case .fr24: return "FR24"
        case .readsb: return "readsb/dump1090"
        case .planefinder: return "Planefinder"
        }
    }

    var defaultWebPath: String {
        switch self {
        case .fr24: return ""
        case .readsb: return "/tar1090/"
        case .planefinder: return "/"
        }
    }
}

struct Feeder: Identifiable, Codable, Equatable {
    var id: String {
        device.id
    }

    let device: DeviceConfig
    let info: FeederInfo?
    let isOnline: Bool

    init(device: DeviceConfig, info: FeederInfo? = nil, isOnline: Bool = false) {
        self.device = device
        self.info = info
        self.isOnline = isOnline
    }
}

struct DeviceConfig: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var ip: String
    var port: Int
    var stationType: StationType
    var webUIPath: String?
    var customLat: Double?
    var customLon: Double?
    var useSSL: Bool

    var scheme: String {
        useSSL ? "https" : "http"
    }

    var resolvedWebURL: URL? {
        if let custom = webUIPath, !custom.isEmpty {
            return URL(string: "\(scheme)://\(ip):\(port)\(custom)")
        }
        switch stationType {
        case .fr24:
            return URL(string: "\(scheme)://\(ip):\(port)")
        case .readsb:
            return URL(string: "\(scheme)://\(ip)\(stationType.defaultWebPath)")
        case .planefinder:
            return URL(string: "\(scheme)://\(ip):\(port)\(stationType.defaultWebPath)")
        }
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        ip: String,
        port: Int? = nil,
        stationType: StationType = .fr24,
        useSSL: Bool = false,
        webUIPath: String? = nil,
        customLat: Double? = nil,
        customLon: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.ip = ip
        self.stationType = stationType
        self.port = port ?? stationType.defaultPort
        self.useSSL = useSSL
        self.webUIPath = webUIPath
        self.customLat = customLat
        self.customLon = customLon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        ip = try container.decode(String.self, forKey: .ip)
        stationType = try container.decodeIfPresent(StationType.self, forKey: .stationType) ?? .fr24
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? stationType.defaultPort
        useSSL = try container.decodeIfPresent(Bool.self, forKey: .useSSL) ?? false
        webUIPath = try container.decodeIfPresent(String.self, forKey: .webUIPath)
        customLat = try container.decodeIfPresent(Double.self, forKey: .customLat)
        customLon = try container.decodeIfPresent(Double.self, forKey: .customLon)
    }
}

struct FeederInfo: Codable, Equatable {
    let aircraftTracked: Int?
    let aircraftADSB: Int?
    let aircraftNonADSB: Int?
    let totalMessages: Int?
    let feedAlias: String?
    let feedStatus: String?
    let receiverConnected: Bool?
    let mlatStatus: String?
    let version: String?
    let buildRevision: String?
    let fr24Key: String?
    let feedLegacyId: String?
    let lastConnected: String?
    let lastRxConnect: String?
    let receiverLat: Double?
    let receiverLon: Double?
    let maxRangeKm: Double?
    let tar1090: Tar1090Stats?

    var formattedMessages: String {
        guard let msgs = totalMessages else { return "-" }
        if msgs >= 1_000_000 {
            return String(format: "%.1fM", Double(msgs) / 1_000_000)
        } else if msgs >= 1000 {
            return String(format: "%.1fK", Double(msgs) / 1000)
        } else {
            return "\(msgs)"
        }
    }
}

enum DistanceUnit: String, CaseIterable, Identifiable {
    case km
    case miles
    case nm

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .km: return "km"
        case .miles: return "mi"
        case .nm: return "NM"
        }
    }

    func convert(_ km: Double) -> Double {
        switch self {
        case .km: return km
        case .miles: return km * 0.621371
        case .nm: return km * 0.539957
        }
    }
}

func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let r = 6371.0
    let dLat = (lat2 - lat1) * .pi / 180
    let dLon = (lon2 - lon1) * .pi / 180
    let a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
        sin(dLon / 2) * sin(dLon / 2)
    return 2 * r * asin(sqrt(a))
}

struct Tar1090Stats: Codable, Equatable {
    let messagesPerSec: Double?
    let signal: Double?
    let noise: Double?
    let peakSignal: Double?
    let tracksTotal: Int?
    let positionsPerSec: Double?
}
