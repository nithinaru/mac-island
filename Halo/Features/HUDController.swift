import AppKit
import Combine
import CoreGraphics
import Foundation
import IOKit
import SwiftUI

@MainActor
final class HUDController: ObservableObject {
    unowned let session: AppSession
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        guard session.settings.hudReplacement else { return }
        installTap()
    }

    func installTap() {
        guard AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << NSEvent.EventType.systemDefined.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<HUDController>.fromOpaque(refcon).takeUnretainedValue()
                return controller.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    nonisolated func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            return Unmanaged.passUnretained(event)
        }
        return Unmanaged.passUnretained(event)
    }

    func setVolumeScalar(_ value: Float) {
        session.island.post(.volume(level: value, muted: value <= 0.001))
    }

    func setBrightness(_ value: Float) {
        session.island.post(.brightness(value))
    }
}

struct HUDMeterView: View {
    var symbol: String
    var value: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.white)
            Capsule()
                .fill(Color.white.opacity(0.15))
                .frame(width: 88, height: 6)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 88 * value)
                }
        }
        .padding(.horizontal, 12)
    }
}
