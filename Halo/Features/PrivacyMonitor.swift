import AVFoundation
import Combine
import CoreMediaIO
import Foundation
import SwiftUI

/// Camera decision (F16): CoreMediaIO's `kCMIODevicePropertyDeviceIsRunningSomewhere`
/// cannot name the capturing app and is sticky/wrong with Continuity Camera, Center Stage,
/// and Desk View. Halo ships **mic-only** and never fills `cameraApps`, so a wrong camera
/// indicator cannot appear.
@MainActor
final class PrivacyMonitor: ObservableObject {
    unowned let session: AppSession
    @Published var status = PrivacyStatus(micApps: [], cameraApps: [], inputLevel: 0)

    private var pollTimer: Timer?
    private var lastMicIDs: Set<String> = []
    private var showing = false
    private var engine: AVAudioEngine?
    private var meterAllowed = false

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        guard session.settings.privacy else { return }
        _ = CoreMediaIOCamera.probe()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        refresh()
    }

    func refresh() {
        guard session.settings.privacy else { return }
        session.exclusivity.monitor.refresh()
        let selfID = Bundle.main.bundleIdentifier
        let mic = session.exclusivity.monitor.inputting.filter { $0.bundleID != selfID }
        let ids = Set(mic.map(\.bundleID))
        let level = mic.isEmpty ? 0 : status.inputLevel
        status = PrivacyStatus(micApps: mic, cameraApps: [], inputLevel: level)

        if ids != lastMicIDs {
            lastMicIDs = ids
            if mic.isEmpty {
                stopMeter()
                if showing {
                    if case .privacy = session.island.transient {
                        session.island.clearTransient()
                    }
                    showing = false
                }
            } else {
                startMeter()
                session.island.post(.privacy(status), duration: nil)
                showing = true
            }
        }

        if mic.isEmpty {
            stopMeter()
        } else if engine == nil {
            startMeter()
        }
    }

    private func startMeter() {
        guard engine == nil else { return }
        if meterAllowed {
            installEngine()
            return
        }
        Task { [weak self] in
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            await MainActor.run {
                self?.meterAllowed = granted
                if granted {
                    self?.installEngine()
                }
            }
        }
    }

    private func installEngine() {
        guard engine == nil else { return }
        let next = AVAudioEngine()
        let input = next.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let rms = PrivacyMonitor.rms(buffer)
            DispatchQueue.main.async {
                self?.applyLevel(rms)
            }
        }
        do {
            try next.start()
            engine = next
        } catch {
            input.removeTap(onBus: 0)
        }
    }

    private func stopMeter() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        if status.inputLevel != 0 {
            status.inputLevel = 0
        }
    }

    private func applyLevel(_ rms: Float) {
        guard !status.micApps.isEmpty else { return }
        let attack: Float = 0.35
        let release: Float = 0.12
        let previous = status.inputLevel
        let next: Float
        if rms > previous {
            next = previous + (rms - previous) * attack
        } else {
            next = previous + (rms - previous) * release
        }
        status.inputLevel = min(1, max(0, next))
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count {
            let sample = channel[i]
            sum += sample * sample
        }
        let root = sqrtf(sum / Float(count))
        return min(1, root * 8)
    }
}

/// Public CoreMediaIO probe. Result is logged for diagnostics and never shown in the island.
enum CoreMediaIOCamera {
    enum Probe {
        case unavailable
        case runningSomewhereUnreliable
        case idle
    }

    static func probe() -> Probe {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
            return .unavailable
        }
        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = Array(repeating: CMIOObjectID(0), count: count)
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, dataSize, &dataUsed, &devices) == noErr else {
            return .unavailable
        }
        var anyRunning = false
        for device in devices {
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            var value: UInt32 = 0
            var used: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            let status = CMIOObjectGetPropertyData(device, &runningAddress, 0, nil, size, &used, &value)
            if status == noErr, value != 0 {
                anyRunning = true
            }
        }
        return anyRunning ? .runningSomewhereUnreliable : .idle
    }
}

struct PrivacyView: View {
    var status: PrivacyStatus
    @EnvironmentObject private var session: AppSession

    private var live: PrivacyStatus { session.privacy.status }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text(live.micApps.map(\.name).joined(separator: ", "))
                    .foregroundStyle(.white)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: 72, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.green)
                            .frame(width: 72 * CGFloat(live.inputLevel), height: 4)
                    }
            }
        }
        .accessibilityLabel("Microphone input level. This is whether the mic is hot, not an in-app mute.")
        .accessibilityValue(live.micApps.map(\.name).joined(separator: ", "))
    }
}
