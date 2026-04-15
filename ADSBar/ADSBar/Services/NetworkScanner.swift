import Foundation

struct DiscoveredFeeder: Identifiable, Equatable {
    let id = UUID().uuidString
    let hostname: String
    let ip: String
    let port: Int
    let stationType: StationType

    static func == (lhs: DiscoveredFeeder, rhs: DiscoveredFeeder) -> Bool {
        lhs.ip == rhs.ip && lhs.stationType == rhs.stationType
    }
}

actor NetworkScanner {
    private let feederAPI = FeederAPIService(timeout: 3)

    func scan(
        localIP: String,
        onFound: @escaping @Sendable (DiscoveredFeeder) -> Void,
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async {
        let parts = localIP.split(separator: ".").map(String.init)
        guard parts.count == 4, let base = parts.dropLast().joined(separator: ".") as String? else { return }

        let ips = (1 ... 254).map { "\(base).\($0)" }
        let total = ips.count
        var checked = 0

        await withTaskGroup(of: Void.self) { group in
            var running = 0
            for ip in ips {
                for type in StationType.allCases where type != .airplanesLive {
                    if running >= 64 {
                        await group.next()
                        running -= 1
                    }
                    running += 1
                    group.addTask { [feederAPI] in
                        let found = await feederAPI.probe(ip: ip, port: type.defaultPort, type: type)

                        if found {
                            let device = DeviceConfig(name: "scan", ip: ip, stationType: type)
                            let info = await feederAPI.fetchFeederInfo(device: device)
                            let name = info?.feedAlias ?? "ADS-B Station"
                            let discovered = DiscoveredFeeder(
                                hostname: name,
                                ip: ip,
                                port: type.defaultPort,
                                stationType: type
                            )
                            onFound(discovered)
                        }
                    }
                }
                checked += 1
                let current = checked
                onProgress(current, total)
            }
            for await _ in group {}
        }
    }
}

func getLocalIPAddress() -> String? {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
    defer { freeifaddrs(ifaddr) }

    for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let addr = ptr.pointee
        guard addr.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

        let name = String(cString: addr.ifa_name)
        guard name.hasPrefix("en") else { continue }

        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(
            addr.ifa_addr,
            socklen_t(addr.ifa_addr.pointee.sa_len),
            &hostname,
            socklen_t(hostname.count),
            nil,
            0,
            NI_NUMERICHOST
        ) == 0 {
            let ip = String(cString: hostname)
            if ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.") {
                return ip
            }
        }
    }
    return nil
}
