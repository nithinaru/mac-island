import AppKit
import SwiftUI

@MainActor
final class NotchWindowManager: NSObject {
    unowned let session: AppSession
    private var window: NotchWindow?
    private var hosting: NSView?
    private var tracking: NSTrackingArea?

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        rebuild()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    @objc private func screensChanged() {
        session.geometry.refresh()
        rebuild()
    }

    func rebuild() {
        session.geometry.refresh()
        let metrics = session.geometry.metrics
        let screen = session.geometry.screen ?? NSScreen.main

        if window == nil, let screen {
            let panel = NotchWindow(screen: screen)
            let root = IslandRootView().environmentObject(session)
            let host = NSHostingView(rootView: root)
            host.frame = CGRect(origin: .zero, size: metrics.windowSize)
            panel.contentView = host
            hosting = host
            window = panel
        }

        guard let window else { return }
        window.setFrame(
            CGRect(origin: metrics.windowOrigin, size: metrics.windowSize),
            display: true
        )
        hosting?.frame = CGRect(origin: .zero, size: metrics.windowSize)
        window.ignoresMouseEvents = false
        window.orderFrontRegardless()
        installTracking()
    }

    private func installTracking() {
        guard let content = window?.contentView else { return }
        if let tracking {
            content.removeTrackingArea(tracking)
        }
        let metrics = session.geometry.metrics
        let slop = MotionConstants.hoverSlop
        let idle = metrics.idleSize
        let areaRect = CGRect(
            x: (metrics.windowSize.width - idle.width) / 2 - slop,
            y: metrics.windowSize.height - idle.height - slop,
            width: idle.width + slop * 2,
            height: idle.height + slop * 2
        )
        let area = NSTrackingArea(
            rect: areaRect,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        content.addTrackingArea(area)
        tracking = area
    }

    func mouseEntered(with event: NSEvent) {
        session.island.setHover(true)
    }

    func mouseExited(with event: NSEvent) {
        session.island.setHover(false)
    }
}
