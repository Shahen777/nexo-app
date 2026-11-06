import Cocoa
import FlutterMacOS
import Sparkle

@MainActor
final class NexoUpdater: NSObject, SPUUpdaterDelegate {
    private let channel: FlutterMethodChannel
    private var controller: SPUStandardUpdaterController?
    private var feedURL: URL?

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "nexo/updater", binaryMessenger: messenger)
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else {
                result(FlutterError(code: "updater_unavailable", message: "Updater unavailable.", details: nil))
                return
            }
            self.handle(call, result: result)
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "checkForUpdates" || call.method == "checkForUpdatesInBackground" else {
            result(FlutterMethodNotImplemented)
            return
        }
        let arguments = call.arguments as? [String: Any]
        if arguments?["safeMode"] as? Bool == true {
            result(false)
            return
        }
        guard let requestedFeed = UpdaterConfiguration.feedURL(from: arguments?["feedUrl"]) else {
            result(FlutterError(code: "invalid_feed", message: "A valid HTTPS update feed is required.", details: nil))
            return
        }
        if let feedURL, feedURL != requestedFeed {
            result(FlutterError(code: "feed_changed", message: "Restart the app to change the update feed.", details: nil))
            return
        }
        do {
            let controller = try updaterController(feed: requestedFeed)
            guard controller.updater.canCheckForUpdates else {
                result(false)
                return
            }
            if call.method == "checkForUpdates" {
                controller.checkForUpdates(nil)
            } else {
                controller.updater.checkForUpdatesInBackground()
            }
            result(true)
        } catch {
            result(FlutterError(code: "updater_start_failed", message: "Unable to start the updater.", details: nil))
        }
    }

    private func updaterController(feed: URL) throws -> SPUStandardUpdaterController {
        if let controller {
            return controller
        }
        feedURL = feed
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        controller.updater.automaticallyChecksForUpdates = false
        controller.updater.automaticallyDownloadsUpdates = false
        controller.updater.sendsSystemProfile = false
        try controller.updater.start()
        self.controller = controller
        return controller
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        return feedURL?.absoluteString
    }
}
