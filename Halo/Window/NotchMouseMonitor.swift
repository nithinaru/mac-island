import AppKit
import SwiftUI

@MainActor
final class NotchMouseMonitor {
    unowned let session: AppSession
    private var local: Any?
    private var global: Any?

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDown, .leftMouseDown
        ]
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
        handle(nil)
    }

    func stop() {
        if let local {
            NSEvent.removeMonitor(local)
        }
        if let global {
            NSEvent.removeMonitor(global)
        }
        local = nil
        global = nil
    }

    func handle(_ event: NSEvent?) {
        let point = NSEvent.mouseLocation
        let hovering = hoverRect().insetBy(dx: -MotionConstants.hoverSlop, dy: -MotionConstants.hoverSlop).contains(point)
        session.windows.setClickThrough(!hovering && session.island.visualState == .idle)

        if event?.type == .rightMouseDown, hovering {
            showContextMenu(at: point)
        }

        session.island.setHover(hovering)
    }

    private func hoverRect() -> CGRect {
        let metrics = session.geometry.metrics
        let size: CGSize
        switch session.island.visualState {
        case .idle:
            size = metrics.idleSize
        case .compact:
            size = metrics.compactSize
        case .expanded:
            size = metrics.expandedSize
        }
        let top = metrics.screenFrame.maxY
        let midX = metrics.windowOrigin.x + metrics.windowSize.width / 2
        return CGRect(
            x: midX - size.width / 2,
            y: top - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func showContextMenu(at point: NSPoint) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(HaloMenuTarget.openSettings), keyEquivalent: "")
        let pauseTitle = session.settings.enforcementEnabled ? "Pause Enforcement" : "Resume Enforcement"
        menu.addItem(withTitle: pauseTitle, action: #selector(HaloMenuTarget.toggleEnforcement), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Halo", action: #selector(HaloMenuTarget.quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = HaloMenuTarget.shared }
        menu.popUp(positioning: nil, at: point, in: nil)
    }
}

final class HaloMenuTarget: NSObject {
    static let shared = HaloMenuTarget()

    @objc func openSettings() {
        Task { @MainActor in AppSession.shared.openSettings() }
    }

    @objc func toggleEnforcement() {
        Task { @MainActor in AppSession.shared.settings.enforcementEnabled.toggle() }
    }

    @objc func quit() {
        Task { @MainActor in AppSession.shared.quit() }
    }
}
