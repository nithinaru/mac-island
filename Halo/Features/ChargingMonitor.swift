import Combine
import Foundation
import IOKit.ps
import SwiftUI

@MainActor
final class ChargingMonitor: ObservableObject {
    unowned let session: AppSession
    private var source: CFRunLoopSource?
    private var lastCharging = false

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        guard session.settings.charging else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ info in
            guard let info else { return }
            let monitor = Unmanaged<ChargingMonitor>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in
                monitor.update()
            }
        }, ctx)?.takeRetainedValue()
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        update()
    }

    func update() {
        guard session.settings.charging else { return }
        let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let list = blob.flatMap { IOPSCopyPowerSourcesList($0)?.takeRetainedValue() as? [CFTypeRef] } ?? []
        guard let first = list.first, let blob,
              let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any]
        else { return }
        let percent = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 0
        let charging = (desc[kIOPSPowerSourceStateKey as String] as? String) == (kIOPSACPowerValue as String)
        if charging && !lastCharging {
            session.island.post(.charging(percent: percent, isCharging: true))
        }
        lastCharging = charging
    }
}

struct ChargingView: View {
    var percent: Int
    var isCharging: Bool
    /// MagSafe / typical connector sits on the leading edge of current MacBooks.
    var fromTrailing: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isCharging ? "bolt.fill" : "battery.100percent")
                .foregroundStyle(.green)
                .symbolEffect(.pulse, isActive: isCharging)
            Text("\(percent)%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .background {
            if isCharging {
                ConnectorRipple(fromTrailing: fromTrailing)
            }
        }
    }
}

private struct ConnectorRipple: View {
    var fromTrailing: Bool

    var body: some View {
        GeometryReader { proxy in
            let origin = CGPoint(
                x: fromTrailing ? proxy.size.width : 0,
                y: proxy.size.height / 2
            )
            ZStack {
                ripple(phase: 0, origin: origin, size: proxy.size)
                ripple(phase: 1, origin: origin, size: proxy.size)
                ripple(phase: 2, origin: origin, size: proxy.size)
            }
        }
        .allowsHitTesting(false)
    }

    private func ripple(phase: Int, origin: CGPoint, size: CGSize) -> some View {
        let span = max(size.width, size.height) * 1.8
        return Circle()
            .stroke(Color.green.opacity(0.55), lineWidth: 1.6)
            .frame(width: 10, height: 10)
            .phaseAnimator([0.0, 1.0]) { content, value in
                content
                    .scaleEffect(1 + value * (span / 10))
                    .opacity(0.7 * (1 - value))
                    .position(origin)
            } animation: { _ in
                .easeOut(duration: 1.35)
                .repeatForever(autoreverses: false)
                .delay(Double(phase) * 0.28)
            }
    }
}
