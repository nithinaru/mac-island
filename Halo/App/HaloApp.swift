import AppKit

@main
final class HaloApp: NSObject, NSApplicationDelegate {
    private let session = AppSession.shared

    static func main() {
        let delegate = HaloApp()
        NSApplication.shared.delegate = delegate
        NSApp.setActivationPolicy(.accessory)
        NSApp.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        session.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }
}
