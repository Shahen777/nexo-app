import Cocoa
import FlutterMacOS
import window

@main
class AppDelegate: FlutterAppDelegate {
    private var updater: NexoUpdater?
    var requestTermination: () -> Void = { WindowPlugin.instance?.handleShouldTerminate() }
    
    @MainActor
    func configureUpdater(messenger: FlutterBinaryMessenger) {
        if updater == nil {
            updater = NexoUpdater(messenger: messenger)
        }
    }

    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        requestTermination()
        return .terminateCancel
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
      return true
    }
    
    override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowPlugin.instance?.handleReopen()
        return false
    }
}
