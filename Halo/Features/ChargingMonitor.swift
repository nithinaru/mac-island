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
            Unmanaged<ChargingMonitor>.fromOpaque(info).takeUnretainedValue().update()
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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isCharging ? "bolt.fill" : "battery.100")
                .foregroundStyle(.green)
            Text("\(percent)%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}
