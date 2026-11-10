import Foundation
import NexoCore

enum NexoShared {
    static let appGroup = "group.app.nexo.vpn"
    static let tunnelBundleSuffix = ".PacketTunnel"

    static var containerURL: URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            fatalError("App Group \(appGroup) is missing from the entitlements")
        }
        return url
    }

    // The Core's home: profiles, providers and spilled responses must be readable by both processes.
    static var homeURL: URL {
        let url = containerURL.appendingPathComponent("home", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var sharedStateURL: URL {
        containerURL.appendingPathComponent("shared_state.json")
    }

    static func initParams() -> String {
        let params: [String: Any] = ["home-dir": homeURL.path, "version": 0]
        let data = try! JSONSerialization.data(withJSONObject: params)
        return String(decoding: data, as: UTF8.self)
    }
}

final class CoreResultHandler: NSObject, NexoMobileResultHandlerProtocol {
    private let block: (Data?) -> Void

    init(_ block: @escaping (Data?) -> Void) {
        self.block = block
    }

    func onResult(_ data: Data?) throws {
        block(data)
    }
}

enum CoreRouting {
    // Calls that change what the running tunnel does go to its Core as well as the app's.
    static let mirrored: Set<String> = [
        "setupConfig", "updateConfig", "changeProxy", "closeConnections", "closeConnection",
        "resetConnections", "clearDnsCache", "updateExternalProvider", "sideLoadExternalProvider",
        "updateGeoData",
    ]

    // Only the tunnel's Core carries traffic, so these are answered by it alone while it runs.
    static let tunnelOnly: Set<String> = [
        "getTraffic", "getTotalTraffic", "resetTraffic", "getConnections", "getConnectionCount",
        "outboundIp", "getMemoryStats",
    ]

    static func methodName(of payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["method"] as? String
    }
}
