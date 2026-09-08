import AppKit
import SwiftUI

@MainActor
final class NotchWindowManager: NSObject {
    unowned let session: AppSession
    private var window: NotchWindow?
    private var hosting: NSView?
    private var tracking: NSTrackingArea?
    private var started = false
    private lazy var mouseMonitor = NotchMouseMonitor(session: session)

    func setClickThrough(_ clickThrough: Bool) {
        window?.ignoresMouseEvents = clickThrough
    }

    init(session: AppSession) {
        self.session = session
        super.init()
    }

    func start() {
        guard !started else {
            rebuild()
            return
        }
        started = true
        rebuild()
        mouseMonitor.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(screensChanged), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensChanged), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensChanged), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensChanged), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func screensChanged() {
        session.geometry.refresh()
        rebuild()
    }

    func rebuild() {
        session.geometry.refresh()
        tearDownWindow()

        let metrics = session.geometry.metrics
        guard let screen = session.geometry.screen ?? NSScreen.preferredIslandScreen else {
            return
        }

        let panel = NotchWindow(screen: screen)
        let root = IslandRootView().environmentObject(session)
        let host = IslandHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: metrics.windowSize)
        panel.contentView = host
        hosting = host
        window = panel

        panel.setFrame(
            CGRect(origin: metrics.windowOrigin, size: metrics.windowSize),
            display: true
        )
        host.frame = CGRect(origin: .zero, size: metrics.windowSize)
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        installTracking()
        mouseMonitor.handle(nil)
    }

    private func tearDownWindow() {
        if let tracking, let content = window?.contentView {
            content.removeTrackingArea(tracking)
        }
        tracking = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window?.close()
        hosting = nil
        window = nil
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

    @objc func mouseEntered(with event: NSEvent) {
        session.island.setHover(true)
    }

    @objc func mouseExited(with event: NSEvent) {
        session.island.setHover(false)
    }
}

private final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        if #available(macOS 14.0, *) {
            safeAreaRegions = []
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
