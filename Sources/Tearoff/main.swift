import AppKit
import TearoffCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Shot.runIfRequested() { NSApp.terminate(nil); return }
        AppController.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Store.shared.saveNow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        AppController.shared.newPad()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar only: no Dock icon, no app switcher entry
app.run()
