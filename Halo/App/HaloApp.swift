import AppKit

@main
final class HaloApp: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: HaloApp?
    private let session = AppSession.shared

    static func main() {
        let delegate = HaloApp()
        retainedDelegate = delegate
        NSApplication.shared.delegate = delegate
        NSApp.setActivationPolicy(.accessory)
        NSApp.run()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        session.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }
}
