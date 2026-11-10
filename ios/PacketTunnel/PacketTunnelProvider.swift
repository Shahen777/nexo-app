import NetworkExtension
import NexoCore

private let ipv4Address = "198.18.0.1"
private let ipv4Mask = "255.255.255.252"
private let ipv6Address = "fdfe:dcba:9876::1"
private let dns4 = "198.18.0.2"
private let dns6 = "fdfe:dcba:9876::2"
private let defaultMtu = 9000

private struct VpnOptions: Decodable {
    let ipv6: Bool
    let dnsHijacking: Bool
    let stack: String
    let routeAddress: [String]
    let mtu: Int?
    let congestionController: String?
}

private struct SharedState: Decodable {
    let vpnOptions: VpnOptions?
}

enum TunnelError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

final class TunCallbacks: NSObject, NexoMobileTunHandlerProtocol {
    // Sockets the extension opens never re-enter its own tunnel on iOS.
    func protect(_ fd: Int32, ret0_: UnsafeMutablePointer<ObjCBool>?) throws {
        ret0_?.pointee = true
    }

    func resolvePackage(_ uid: Int32, error: NSErrorPointer) -> String {
        ""
    }

    func resolveUid(_ protocol: Int32, source: String?, target: String?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        ret0_?.pointee = -1
    }
}

class PacketTunnelProvider: NEPacketTunnelProvider {
    private let callbacks = TunCallbacks()

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let raw: [String: Any]
        let state: SharedState
        do {
            let data = try Data(contentsOf: NexoShared.sharedStateURL)
            raw = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            state = try JSONDecoder().decode(SharedState.self, from: data)
        } catch {
            completionHandler(TunnelError.message("Open Nexo once to prepare the connection"))
            return
        }
        guard let vpn = state.vpnOptions, let setup = raw["setupParams"],
              let setupData = try? JSONSerialization.data(withJSONObject: setup)
        else {
            completionHandler(TunnelError.message("Choose a server in Nexo first"))
            return
        }
        let setupParams = String(decoding: setupData, as: UTF8.self)
        NexoMobileQuickSetup(NexoShared.initParams(), setupParams, CoreResultHandler { [weak self] result in
            let message = result.map { String(decoding: $0, as: UTF8.self) } ?? ""
            guard message.isEmpty else {
                completionHandler(TunnelError.message(message))
                return
            }
            self?.applySettings(vpn, completionHandler: completionHandler)
        })
    }

    private func applySettings(_ vpn: VpnOptions, completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let mtu = (vpn.mtu ?? 0) > 0 ? min(max(vpn.mtu!, 1280), 65535) : defaultMtu
        settings.mtu = NSNumber(value: mtu)

        let ipv4 = NEIPv4Settings(addresses: [ipv4Address], subnetMasks: [ipv4Mask])
        ipv4.includedRoutes = routes(vpn.routeAddress, ipv6: false) ?? [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        var servers = [dns4]
        if vpn.ipv6 {
            let ipv6 = NEIPv6Settings(addresses: [ipv6Address], networkPrefixLengths: [126])
            ipv6.includedRoutes = routes6(vpn.routeAddress) ?? [NEIPv6Route.default()]
            settings.ipv6Settings = ipv6
            servers.append(dns6)
        }
        let dnsSettings = NEDNSSettings(servers: servers)
        dnsSettings.matchDomains = [""]
        settings.dnsSettings = dnsSettings

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else { return }
            if let error {
                completionHandler(error)
                return
            }
            guard let fd = self.tunnelFileDescriptor else {
                completionHandler(TunnelError.message("No tunnel descriptor"))
                return
            }
            let tunOptions = ["mtu": mtu, "congestion-controller": vpn.congestionController ?? ""] as [String: Any]
            let optionsJson = String(decoding: try! JSONSerialization.data(withJSONObject: tunOptions), as: UTF8.self)
            let address = vpn.ipv6 ? "\(ipv4Address)/30,\(ipv6Address)/126" : "\(ipv4Address)/30"
            let dns = vpn.dnsHijacking ? "0.0.0.0" : servers.joined(separator: ",")
            // The Core closes the descriptor it is given; the original stays with the packet flow.
            let started = NexoMobileStartTun(dup(fd), self.callbacks, vpn.stack, address, dns, optionsJson)
            completionHandler(started ? nil : TunnelError.message("The tunnel did not start"))
        }
    }

    private func routes(_ cidrs: [String], ipv6: Bool) -> [NEIPv4Route]? {
        let parsed: [NEIPv4Route] = cidrs.compactMap { cidr in
            let parts = cidr.split(separator: "/")
            guard parts.count == 2, !parts[0].contains(":"), let bits = Int(parts[1]), (0...32).contains(bits) else {
                return nil
            }
            let mask = bits == 0 ? 0 : UInt32.max << (32 - UInt32(bits))
            let maskString = [24, 16, 8, 0].map { String((mask >> UInt32($0)) & 0xff) }.joined(separator: ".")
            return NEIPv4Route(destinationAddress: String(parts[0]), subnetMask: maskString)
        }
        return parsed.isEmpty ? nil : parsed
    }

    private func routes6(_ cidrs: [String]) -> [NEIPv6Route]? {
        let parsed: [NEIPv6Route] = cidrs.compactMap { cidr in
            let parts = cidr.split(separator: "/")
            guard parts.count == 2, parts[0].contains(":"), let bits = Int(parts[1]) else { return nil }
            return NEIPv6Route(destinationAddress: String(parts[0]), networkPrefixLength: NSNumber(value: bits))
        }
        return parsed.isEmpty ? nil : parsed
    }

    // NEPacketTunnelFlow keeps its utun socket private; find it among the open descriptors.
    private var tunnelFileDescriptor: Int32? {
        var buffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        for fd: Int32 in 0...1024 {
            var length = socklen_t(buffer.count)
            if getsockopt(fd, 2, 2, &buffer, &length) == 0, String(cString: buffer).hasPrefix("utun") {
                return fd
            }
        }
        return packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        NexoMobileStopTun()
        NexoMobileStopListener()
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        let payload = String(decoding: messageData, as: UTF8.self)
        NexoMobileInvokeMethod(payload, CoreResultHandler { result in
            completionHandler?(result)
        })
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        NexoMobileForceGC()
        completionHandler()
    }
}
