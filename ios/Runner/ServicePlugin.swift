import Flutter
import NetworkExtension
import NexoCore

/// The iOS side of `lib/plugins/service.dart`: the app's own Core answers method calls, and the
/// Packet Tunnel extension runs a second Core started from the shared state the app writes.
final class ServicePlugin: NSObject, FlutterPlugin {
    private static let serviceChannelName = "com.follow.clash/service"
    private static let coreChannelName = "com.follow.clash/core"

    private let channel: FlutterMethodChannel
    private var commandRevision = 0
    private var runRequested = false
    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var lastStatus: NEVPNStatus = .invalid

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()
        let channel = FlutterMethodChannel(name: serviceChannelName, binaryMessenger: messenger)
        let instance = ServicePlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
        let coreChannel = FlutterMethodChannel(
            name: coreChannelName,
            binaryMessenger: messenger,
            codec: FlutterStandardMethodCodec.sharedInstance(),
            taskQueue: messenger.makeBackgroundTaskQueue?()
        )
        coreChannel.setMethodCallHandler { call, result in
            guard call.method == "invokeMethod", let payload = call.arguments as? String else {
                result(FlutterMethodNotImplemented)
                return
            }
            instance.invokeCore(payload, result: result)
        }
        instance.observeStatus()
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init":
            NexoMobileSetEventListener(CoreResultHandler { [weak self] data in
                self?.sendEvent(data ?? Data())
            })
            result("")
        case "shutdown":
            NexoMobileSetEventListener(nil)
            result(true)
        case "syncState":
            result(syncState(call.arguments as? String))
        case "start":
            commandRevision = call.arguments as? Int ?? commandRevision
            runRequested = true
            startTunnel()
            result(true)
        case "stop":
            commandRevision = call.arguments as? Int ?? commandRevision
            runRequested = false
            manager?.connection.stopVPNTunnel()
            result(true)
        case "getRunTime":
            let date = manager?.connection.status == .connected ? manager?.connection.connectedDate : nil
            result(date.map { Int($0.timeIntervalSince1970 * 1000) } ?? 0)
        case "homeDir":
            result(NexoShared.homeURL.path)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func syncState(_ json: String?) -> String {
        guard let json, let data = json.data(using: .utf8) else {
            return "Invalid shared state"
        }
        do {
            try data.write(to: NexoShared.sharedStateURL, options: .atomic)
            return ""
        } catch {
            return error.localizedDescription
        }
    }

    private var tunnelSession: NETunnelProviderSession? {
        guard let session = manager?.connection as? NETunnelProviderSession,
              session.status == .connected
        else { return nil }
        return session
    }

    private func invokeCore(_ payload: String, result: @escaping FlutterResult) {
        let method = CoreRouting.methodName(of: payload) ?? ""
        let session = tunnelSession
        if let session, CoreRouting.tunnelOnly.contains(method) {
            sendToTunnel(session, payload) { data in
                result(data.map { FlutterStandardTypedData(bytes: $0) })
            }
            return
        }
        NexoMobileInvokeMethod(payload, CoreResultHandler { data in
            result(data.map { FlutterStandardTypedData(bytes: $0) })
        })
        if let session, CoreRouting.mirrored.contains(method) {
            sendToTunnel(session, payload) { _ in }
        }
    }

    private func sendToTunnel(_ session: NETunnelProviderSession, _ payload: String, reply: @escaping (Data?) -> Void) {
        do {
            try session.sendProviderMessage(Data(payload.utf8), responseHandler: reply)
        } catch {
            reply(nil)
        }
    }

    private func sendEvent(_ data: Data) {
        DispatchQueue.main.async {
            self.channel.invokeMethod("event", arguments: FlutterStandardTypedData(bytes: data))
        }
    }

    private func loadManager(_ done: @escaping (NETunnelProviderManager?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            DispatchQueue.main.async {
                let existing = managers?.first
                self.manager = existing
                done(existing)
            }
        }
    }

    private func startTunnel() {
        loadManager { existing in
            let manager = existing ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = (Bundle.main.bundleIdentifier ?? "") + NexoShared.tunnelBundleSuffix
            proto.serverAddress = "Nexo"
            manager.protocolConfiguration = proto
            manager.localizedDescription = "Nexo"
            manager.isEnabled = true
            manager.saveToPreferences { error in
                if error != nil {
                    self.reportStopped()
                    return
                }
                // A saved configuration is only usable once it has been loaded back.
                manager.loadFromPreferences { _ in
                    DispatchQueue.main.async {
                        self.manager = manager
                        guard self.runRequested else { return }
                        do {
                            try manager.connection.startVPNTunnel()
                        } catch {
                            self.reportStopped()
                        }
                    }
                }
            }
        }
    }

    private func observeStatus() {
        loadManager { _ in }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, let connection = notification.object as? NEVPNConnection else { return }
            let previous = self.lastStatus
            self.lastStatus = connection.status
            // Saving the configuration also reports disconnected; only a run that began can end.
            let wasRunning = [.connecting, .connected, .reasserting, .disconnecting].contains(previous)
            if connection.status == .disconnected, wasRunning, self.runRequested {
                self.reportStopped()
            }
        }
    }

    private func reportStopped() {
        DispatchQueue.main.async {
            self.runRequested = false
            self.channel.invokeMethod("stopped", arguments: self.commandRevision)
        }
    }
}
