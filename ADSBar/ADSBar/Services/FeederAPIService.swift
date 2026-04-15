import Foundation

actor FeederAPIService {
    private let session: URLSession

    init(timeout: TimeInterval = 10) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 5
        session = URLSession(configuration: config)
    }

    func fetchFeederInfo(device: DeviceConfig) async -> FeederInfo? {
        switch device.stationType {
        case .fr24: return await fetchFR24Info(device: device)
        case .readsb: return await fetchReadsbInfo(device: device)
        case .planefinder: return await fetchPlaneFinderInfo(device: device)
        case .airplanesLive: return await fetchAirplanesLiveInfo(device: device)
        }
    }

    func probe(ip: String, port: Int, type: StationType) async -> Bool {
        let path: String
        switch type {
        case .fr24: path = "/monitor.json"
        case .readsb: path = "/data/aircraft.json"
        case .planefinder: path = "/ajax/stats"
        case .airplanesLive: path = "/feed-status"
        }
        let scheme = type == .airplanesLive ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(ip):\(port)\(path)") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - FR24

    private func fetchFR24Info(device: DeviceConfig) async -> FeederInfo? {
        guard let url = URL(string: "\(device.scheme)://\(device.ip):\(device.port)/monitor.json") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            guard let info = Self.parseMonitorJSON(data) else { return nil }

            let stats = await fetchTar1090Stats(device: device)
            let rangeData = await fetchTar1090Range(device: device)

            return FeederInfo(
                aircraftTracked: info.aircraftTracked, aircraftADSB: info.aircraftADSB,
                aircraftNonADSB: info.aircraftNonADSB, totalMessages: info.totalMessages,
                feedAlias: info.feedAlias, feedStatus: info.feedStatus,
                receiverConnected: info.receiverConnected, mlatStatus: info.mlatStatus,
                version: info.version, buildRevision: info.buildRevision,
                fr24Key: info.fr24Key, feedLegacyId: info.feedLegacyId,
                lastConnected: info.lastConnected, lastRxConnect: info.lastRxConnect,
                receiverLat: rangeData?.lat ?? device.customLat,
                receiverLon: rangeData?.lon ?? device.customLon,
                maxRangeKm: rangeData?.maxRange, tar1090: stats,
                beastClients: nil, mlatPeers: nil, mlatMessageRate: nil,
                avgKbitS: nil, rtt: nil, totalPositions: nil, mapLink: nil, connectionTime: nil
            )
        } catch {
            return nil
        }
    }

    private func fetchTar1090Stats(device: DeviceConfig) async -> Tar1090Stats? {
        guard let url = URL(string: "\(device.scheme)://\(device.ip)/tar1090/data/stats.json") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            return Self.parseTar1090Stats(data)
        } catch {
            return nil
        }
    }

    private struct RangeResult {
        let lat: Double?
        let lon: Double?
        let maxRange: Double?
    }

    private func fetchTar1090Range(device: DeviceConfig) async -> RangeResult? {
        guard let url = URL(string: "\(device.scheme)://\(device.ip)/tar1090/data/aircraft.json") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let aircraft = json["aircraft"] as? [[String: Any]] ?? []
            let receiver = await fetchTar1090Receiver(device: device)
            let rxLat = receiver?.lat ?? device.customLat
            let rxLon = receiver?.lon ?? device.customLon

            var maxRange: Double?
            if let rxLat, let rxLon, rxLat != 0, rxLon != 0 {
                for ac in aircraft {
                    guard let acLat = ac["lat"] as? Double,
                          let acLon = ac["lon"] as? Double else { continue }
                    let dist = haversineDistance(lat1: rxLat, lon1: rxLon, lat2: acLat, lon2: acLon)
                    if maxRange == nil || dist > maxRange! {
                        maxRange = dist
                    }
                }
            }
            return RangeResult(lat: rxLat, lon: rxLon, maxRange: maxRange)
        } catch {
            return nil
        }
    }

    // MARK: - readsb/dump1090

    private func fetchReadsbInfo(device: DeviceConfig) async -> FeederInfo? {
        let scheme = device.scheme
        let ip = device.ip
        let port = device.port
        guard let url = URL(string: "\(scheme)://\(ip):\(port)/data/aircraft.json") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let aircraft = json["aircraft"] as? [[String: Any]] ?? []
            let totalMessages = json["messages"] as? Int
            let totalAC = aircraft.count
            let adsbCount = aircraft.filter { ($0["seen_pos"] as? Double) != nil }.count

            var stats: Tar1090Stats?
            if let statsURL = URL(string: "\(scheme)://\(ip):\(port)/data/stats.json") {
                if let (sData, sResp) = try? await session.data(from: statsURL),
                   let sHTTP = sResp as? HTTPURLResponse, sHTTP.statusCode == 200 {
                    stats = Self.parseTar1090Stats(sData)
                }
            }

            let receiver = await fetchReceiverJSON(device: device)
            let rxLat = receiver?.lat ?? device.customLat
            let rxLon = receiver?.lon ?? device.customLon

            var maxRange: Double?
            if let rxLat, let rxLon, rxLat != 0, rxLon != 0 {
                for ac in aircraft {
                    guard let acLat = ac["lat"] as? Double,
                          let acLon = ac["lon"] as? Double else { continue }
                    let dist = haversineDistance(lat1: rxLat, lon1: rxLon, lat2: acLat, lon2: acLon)
                    if maxRange == nil || dist > maxRange! {
                        maxRange = dist
                    }
                }
            }

            return FeederInfo(
                aircraftTracked: totalAC,
                aircraftADSB: adsbCount,
                aircraftNonADSB: totalAC - adsbCount,
                totalMessages: totalMessages,
                feedAlias: nil, feedStatus: nil,
                receiverConnected: true, mlatStatus: nil,
                version: receiver?.version ?? (json["version"] as? String), buildRevision: nil,
                fr24Key: nil, feedLegacyId: nil,
                lastConnected: nil, lastRxConnect: nil,
                receiverLat: rxLat, receiverLon: rxLon,
                maxRangeKm: maxRange, tar1090: stats,
                beastClients: nil, mlatPeers: nil, mlatMessageRate: nil,
                avgKbitS: nil, rtt: nil, totalPositions: nil, mapLink: nil, connectionTime: nil
            )
        } catch {
            return nil
        }
    }

    // MARK: - Planefinder

    private func fetchPlaneFinderInfo(device: DeviceConfig) async -> FeederInfo? {
        let scheme = device.scheme
        let ip = device.ip
        let port = device.port

        // Fetch stats
        guard let statsURL = URL(string: "\(scheme)://\(ip):\(port)/ajax/stats") else { return nil }
        do {
            let (statsData, statsResp) = try await session.data(from: statsURL)
            guard let statsHTTP = statsResp as? HTTPURLResponse,
                  statsHTTP.statusCode == 200 else { return nil }
            guard let stats = try? JSONSerialization.jsonObject(with: statsData) as? [String: Any] else { return nil }

            let totalMessages = stats["total_modes_packets"] as? Int
            let msgsPerSec = stats["total_modes_packets_ps"] as? Double
                ?? (stats["total_modes_packets_ps"] as? Int).map(Double.init)
            let receiverBytesIn = stats["receiver_bytes_in_ps"] as? Int

            // Fetch aircraft data for count and range
            var aircraftCount: Int?
            var rxLat: Double?
            var rxLon: Double?
            var maxRange: Double?

            if let acURL = URL(string: "\(scheme)://\(ip):\(port)/ajax/aircraft") {
                if let (acData, acResp) = try? await session.data(from: acURL),
                   let acHTTP = acResp as? HTTPURLResponse, acHTTP.statusCode == 200,
                   let acJSON = try? JSONSerialization.jsonObject(with: acData) as? [String: Any] {
                    let aircraft = acJSON["aircraft"] as? [String: [String: Any]] ?? [:]
                    aircraftCount = aircraft.count

                    if let user = acJSON["user"] as? [String: Any] {
                        rxLat = (user["user_lat"] as? String).flatMap(Double.init)
                        rxLon = (user["user_lon"] as? String).flatMap(Double.init)
                    }

                    let lat = rxLat ?? device.customLat
                    let lon = rxLon ?? device.customLon
                    if let lat, let lon, lat != 0, lon != 0 {
                        for (_, ac) in aircraft {
                            guard let acLat = ac["lat"] as? Double,
                                  let acLon = ac["lon"] as? Double else { continue }
                            let dist = haversineDistance(lat1: lat, lon1: lon, lat2: acLat, lon2: acLon)
                            if maxRange == nil || dist > maxRange! {
                                maxRange = dist
                            }
                        }
                    }
                }
            }

            return FeederInfo(
                aircraftTracked: aircraftCount,
                aircraftADSB: nil,
                aircraftNonADSB: nil,
                totalMessages: totalMessages,
                feedAlias: nil, feedStatus: nil,
                receiverConnected: receiverBytesIn != nil && receiverBytesIn! > 0,
                mlatStatus: nil,
                version: stats["client_version"] as? String, buildRevision: nil,
                fr24Key: nil, feedLegacyId: nil,
                lastConnected: nil, lastRxConnect: nil,
                receiverLat: rxLat ?? device.customLat, receiverLon: rxLon ?? device.customLon,
                maxRangeKm: maxRange,
                tar1090: Tar1090Stats(
                    messagesPerSec: msgsPerSec,
                    signal: nil, noise: nil, peakSignal: nil, tracksTotal: nil,
                    positionsPerSec: nil
                ),
                beastClients: nil, mlatPeers: nil, mlatMessageRate: nil,
                avgKbitS: nil, rtt: nil, totalPositions: nil, mapLink: nil, connectionTime: nil
            )
        } catch {
            return nil
        }
    }

    // MARK: - Airplanes.Live

    private func fetchAirplanesLiveInfo(device: DeviceConfig) async -> FeederInfo? {
        guard let url = URL(string: "https://\(device.ip)/feed-status") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let beastClients = json["beast_clients"] as? [[String: Any]] ?? []
            let mlatClients = json["mlat_clients"] as? [[String: Any]] ?? []
            let mapLink = json["map_link"] as? String

            // Aggregate beast client stats (sum across all clients)
            var totalMsgsS: Double = 0
            var totalPosS: Double = 0
            var totalKbitS: Double = 0
            var totalPos = 0
            var bestRtt: Double = -1
            var maxConnTime = 0
            var activeBeastClients = 0

            for client in beastClients {
                let msgsS = client["msgs_s"] as? Double ?? 0
                let posS = client["pos_s"] as? Double ?? 0
                let kbitS = client["avg_kbit_s"] as? Double ?? 0
                let pos = client["pos"] as? Int ?? 0
                let rtt = client["rtt"] as? Double ?? -1
                let connTime = client["conn_time"] as? Int ?? 0

                totalMsgsS += msgsS
                totalPosS += posS
                totalKbitS += kbitS
                totalPos += pos
                if rtt > 0 { bestRtt = bestRtt > 0 ? min(bestRtt, rtt) : rtt }
                maxConnTime = max(maxConnTime, connTime)

                if msgsS > 0 { activeBeastClients += 1 }
            }

            // MLAT info from first client
            let mlatPeers = mlatClients.first?["peer_count"] as? Int
            let mlatMessageRate = mlatClients.first?["message_rate"] as? Double
            let mlatLat = mlatClients.first?["lat"] as? Double
            let mlatLon = mlatClients.first?["lon"] as? Double

            let receiverLat = mlatLat ?? device.customLat
            let receiverLon = mlatLon ?? device.customLon

            // Fetch aircraft count from REST API if we have coordinates
            // Delay to respect airplanes.live rate limit (1 req/sec)
            var aircraftCount: Int?
            if let lat = receiverLat, let lon = receiverLon {
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                aircraftCount = await fetchAirplanesLiveAircraftCount(lat: lat, lon: lon)
            }

            let isConnected = !beastClients.isEmpty
            let hasMlat = !mlatClients.isEmpty

            return FeederInfo(
                aircraftTracked: aircraftCount,
                aircraftADSB: nil,
                aircraftNonADSB: nil,
                totalMessages: nil,
                feedAlias: nil, feedStatus: isConnected ? "connected" : "disconnected",
                receiverConnected: isConnected,
                mlatStatus: hasMlat ? "ok (\(mlatPeers ?? 0) peers)" : nil,
                version: nil, buildRevision: nil,
                fr24Key: nil, feedLegacyId: nil,
                lastConnected: nil, lastRxConnect: nil,
                receiverLat: receiverLat, receiverLon: receiverLon,
                maxRangeKm: nil,
                tar1090: Tar1090Stats(
                    messagesPerSec: totalMsgsS > 0 ? totalMsgsS : nil,
                    signal: nil, noise: nil, peakSignal: nil, tracksTotal: nil,
                    positionsPerSec: totalPosS > 0 ? totalPosS : nil
                ),
                beastClients: beastClients.count,
                mlatPeers: mlatPeers,
                mlatMessageRate: mlatMessageRate,
                avgKbitS: totalKbitS,
                rtt: bestRtt > 0 ? bestRtt : nil,
                totalPositions: totalPos,
                mapLink: mapLink,
                connectionTime: maxConnTime > 0 ? maxConnTime : nil
            )
        } catch {
            return nil
        }
    }

    private func fetchAirplanesLiveAircraftCount(lat: Double, lon: Double) async -> Int? {
        guard let url = URL(string: "https://api.airplanes.live/v2/point/\(lat)/\(lon)/250") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return json["total"] as? Int ?? (json["ac"] as? [[String: Any]])?.count
        } catch {
            return nil
        }
    }

    // MARK: - Parsing

    private static func parseMonitorJSON(_ data: Data) -> FeederInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        func str(_ key: String) -> String? {
            json[key] as? String
        }
        func int(_ key: String) -> Int? {
            (json[key] as? String).flatMap(Int.init)
        }

        return FeederInfo(
            aircraftTracked: int("feed_num_ac_tracked"),
            aircraftADSB: int("feed_num_ac_adsb_tracked"),
            aircraftNonADSB: int("feed_num_ac_non_adsb_tracked"),
            totalMessages: int("num_messages"),
            feedAlias: str("feed_alias"),
            feedStatus: str("feed_status"),
            receiverConnected: str("rx_connected") == "1",
            mlatStatus: str("mlat-ok"),
            version: str("build_version"),
            buildRevision: str("build_revision"),
            fr24Key: str("fr24key"),
            feedLegacyId: str("feed_legacy_id"),
            lastConnected: str("last_rx_connect_time_s"),
            lastRxConnect: str("last_rx_connect_status"),
            receiverLat: nil, receiverLon: nil,
            maxRangeKm: nil, tar1090: nil,
            beastClients: nil, mlatPeers: nil, mlatMessageRate: nil,
            avgKbitS: nil, rtt: nil, totalPositions: nil, mapLink: nil, connectionTime: nil
        )
    }

    private struct ReceiverInfo {
        let lat: Double?
        let lon: Double?
        let version: String?
    }

    private func fetchTar1090Receiver(device: DeviceConfig) async -> ReceiverInfo? {
        guard let url = URL(string: "\(device.scheme)://\(device.ip)/tar1090/data/receiver.json") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return ReceiverInfo(
                lat: json["lat"] as? Double,
                lon: json["lon"] as? Double,
                version: json["version"] as? String
            )
        } catch {
            return nil
        }
    }

    private func fetchReceiverJSON(device: DeviceConfig) async -> ReceiverInfo? {
        guard let url = URL(string: "\(device.scheme)://\(device.ip):\(device.port)/data/receiver.json") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return ReceiverInfo(
                lat: json["lat"] as? Double,
                lon: json["lon"] as? Double,
                version: json["version"] as? String
            )
        } catch {
            return nil
        }
    }

    // tar1090 stats.json has nested time buckets: last1min, last5min, last15min, total
    private static func parseTar1090Stats(_ data: Data) -> Tar1090Stats? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        guard let last1min = json["last1min"] as? [String: Any] else { return nil }
        let start = last1min["start"] as? Double ?? 0
        let end = last1min["end"] as? Double ?? 0
        let duration = end - start
        guard duration > 0 else { return nil }

        let messages = last1min["messages"] as? Int ?? 0
        let msgsPerSec = Double(messages) / duration

        let local = last1min["local"] as? [String: Any]
        let signal = local?["signal"] as? Double
        let noise = local?["noise"] as? Double
        let peakSignal = local?["peak_signal"] as? Double

        let cpr = last1min["cpr"] as? [String: Any]
        let globalOk = cpr?["global_ok"] as? Int ?? 0
        let localOk = cpr?["local_ok"] as? Int ?? 0
        let posPerSec = Double(globalOk + localOk) / duration

        let total = json["total"] as? [String: Any]
        let tracks = total?["tracks"] as? [String: Any]
        let tracksAll = tracks?["all"] as? Int

        return Tar1090Stats(
            messagesPerSec: msgsPerSec,
            signal: signal,
            noise: noise,
            peakSignal: peakSignal,
            tracksTotal: tracksAll,
            positionsPerSec: posPerSec
        )
    }
}
