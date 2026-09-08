import AppKit
import Combine
import SwiftUI

@MainActor
final class ScreenGeometryStore: ObservableObject {
    @Published private(set) var metrics: NotchMetrics
    @Published private(set) var screen: NSScreen?

    init() {
        metrics = ScreenGeometryStore.metrics(for: NSScreen.notched ?? NSScreen.main ?? NSScreen.screens.first)
        screen = NSScreen.notched ?? NSScreen.main ?? NSScreen.screens.first
    }

    func refresh() {
        let next = NSScreen.notched ?? NSScreen.main ?? NSScreen.screens.first
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
                compactSize: CGSize(width: fallback.width + 72, height: fallback.height),
                expandedSize: CGSize(width: 420, height: 220),
                windowSize: CGSize(width: 520, height: 320),
                windowOrigin: .zero,
                isFallbackPill: true
            )
        }

        let hasNotch = screen.hasNotch
        let notchHeight = hasNotch ? screen.notchHeight : fallback.height
        let notchWidth = hasNotch ? max(screen.notchWidth, fallback.width) : fallback.width
        let idle = CGSize(width: notchWidth, height: notchHeight)
        let compact = CGSize(width: notchWidth + 84, height: notchHeight)
        let expanded = CGSize(width: max(420, notchWidth + 180), height: notchHeight + 188)
        let windowSize = CGSize(width: expanded.width + 96, height: expanded.height + 72)
        let origin = CGPoint(
            x: screen.frame.midX - windowSize.width / 2,
            y: screen.frame.maxY - windowSize.height
        )

        return NotchMetrics(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            hasNotch: hasNotch,
            notchWidth: notchWidth,
            notchHeight: notchHeight,
            idleSize: idle,
            compactSize: compact,
            expandedSize: expanded,
            windowSize: windowSize,
            windowOrigin: origin,
            isFallbackPill: !hasNotch
        )
    }
}

extension NSScreen {
    var hasNotch: Bool { safeAreaInsets.top > 0 }

    var notchHeight: CGFloat { safeAreaInsets.top }

    var notchWidth: CGFloat {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return 0 }
        return frame.width - left.width - right.width
    }

    static var notched: NSScreen? {
        screens.first(where: \.hasNotch)
    }
}
