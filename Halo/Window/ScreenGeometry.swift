import AppKit
import Combine
import SwiftUI

@MainActor
final class ScreenGeometryStore: ObservableObject {
    @Published private(set) var metrics: NotchMetrics
    @Published private(set) var screen: NSScreen?

    init() {
        let next = NSScreen.preferredIslandScreen
        screen = next
        metrics = ScreenGeometryStore.metrics(for: next)
    }

    func refresh() {
        let next = NSScreen.preferredIslandScreen
        screen = next
        metrics = ScreenGeometryStore.metrics(for: next)
    }

    static func metrics(for screen: NSScreen?) -> NotchMetrics {
        let fallback = NotchMetrics.fallbackNotch
        guard let screen else {
            return NotchMetrics(
                screenFrame: .zero,
                visibleFrame: .zero,
                hasNotch: false,
                notchWidth: fallback.width,
                notchHeight: fallback.height,
                idleSize: fallback,
                compactSize: compactSize(idle: fallback),
                expandedSize: expandedSize(idle: fallback),
                windowSize: windowSize(expanded: expandedSize(idle: fallback)),
                windowOrigin: .zero,
                isFallbackPill: true
            )
        }

        let layout = screen.notchLayout
        let idle = layout.idleSize
        let compact = compactSize(idle: idle)
        let expanded = expandedSize(idle: idle)
        let size = windowSize(expanded: expanded)
        let origin = CGPoint(
            x: layout.centerX - size.width / 2,
            y: screen.frame.maxY - size.height
        )

        return NotchMetrics(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            hasNotch: layout.hasNotch,
            notchWidth: idle.width,
            notchHeight: idle.height,
            idleSize: idle,
            compactSize: compact,
            expandedSize: expanded,
            windowSize: size,
            windowOrigin: origin,
            isFallbackPill: layout.isFallback
        )
    }

    private static func compactSize(idle: CGSize) -> CGSize {
        CGSize(width: idle.width + 72, height: idle.height)
    }

    private static func expandedSize(idle: CGSize) -> CGSize {
        CGSize(width: max(320, idle.width + 140), height: idle.height + 76)
    }

    private static func windowSize(expanded: CGSize) -> CGSize {
        let slop = MotionConstants.hoverSlop
        return CGSize(width: expanded.width + slop * 2, height: expanded.height + slop)
    }
}

extension NSScreen {
    var hasNotch: Bool { safeAreaInsets.top > 0 }

    var notchHeight: CGFloat { safeAreaInsets.top }

    var notchWidth: CGFloat {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return 0 }
        return frame.width - left.width - right.width
    }

    var isBuiltinDisplay: Bool {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(number.uint32Value) != 0
    }

    /// Built-in notched display when present; otherwise the remaining screen (lid closed / no notch).
    static var preferredIslandScreen: NSScreen? {
        let attached = screens
        if let builtinNotch = attached.first(where: { $0.hasNotch && $0.isBuiltinDisplay }) {
            return builtinNotch
        }
        if let notched = attached.first(where: \.hasNotch) {
            return notched
        }
        return NSScreen.main ?? attached.first
    }

    static var notched: NSScreen? {
        screens.first(where: \.hasNotch)
    }

    fileprivate var notchLayout: NotchLayout {
        let fallback = NotchMetrics.fallbackNotch
        guard hasNotch else {
            return NotchLayout(
                hasNotch: false,
                isFallback: true,
                idleSize: fallback,
                centerX: frame.midX
            )
        }

        let height = notchHeight
        let left = auxiliaryTopLeftArea
        let right = auxiliaryTopRightArea
        let measuredWidth: CGFloat
        let centerX: CGFloat

        if let left, let right {
            measuredWidth = frame.width - left.width - right.width
            centerX = frame.minX + left.width + measuredWidth / 2
        } else {
            measuredWidth = 0
            centerX = frame.midX
        }

        let width = measuredWidth > 1 ? measuredWidth : fallback.width
        return NotchLayout(
            hasNotch: true,
            isFallback: false,
            idleSize: CGSize(width: width, height: height > 0 ? height : fallback.height),
            centerX: centerX
        )
    }
}

private struct NotchLayout {
    var hasNotch: Bool
    var isFallback: Bool
    var idleSize: CGSize
    var centerX: CGFloat
}
