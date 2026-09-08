import Accelerate
import Combine
import CoreAudio
import Foundation

/// Compact-state meters from a public Core Audio **process tap** on Music.app.
///
/// Public route: `CATapDescription` + `AudioHardwareCreateProcessTap` (macOS 14.2+)
/// feeding a private aggregate, then an IOProc. That is the supported way to read
/// another process's output mix.
///
/// Gaps (not private APIs — just unavailable or TCC-gated):
/// - Capturing another app usually needs **system audio capture / Screen Recording** TCC.
///   This folder cannot add `NSAudioCaptureUsageDescription` to Info.plist.
/// - No public per-app output VU besides the process tap.
/// - Default-device volume scalar is not signal level.
/// - **MediaRemote is not used.**
///
/// Fallback: `level` / `bars` stay at rest (no canned loop). Retry when Music appears in HAL.
@MainActor
final class MusicProcessTap: ObservableObject {
    unowned let session: AppSession
    @Published var level: Float = 0
    @Published var bars: [Float] = Array(repeating: 0.08, count: 7)
    @Published private(set) var tapActive = false
    @Published private(set) var lastError: String?

    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var processListenerInstalled = false
    private var cancellables: Set<AnyCancellable> = []
    private let audioQueue = DispatchQueue(label: "halo.music-process-tap", qos: .userInteractive)
    private let meter = ProcessTapMeter()
    private var running = false

    static let restBars: [Float] = Array(repeating: 0.08, count: 7)

    init(session: AppSession) {
        self.session = session
        meter.onPublish = { [weak self] level, bars in
            Task { @MainActor in
                guard let self else { return }
                self.level = level
                if self.session.settings.reactiveWaveform, self.session.music.snapshot?.isPlaying == true {
                    self.bars = bars
                } else {
                    self.bars = Self.restBars
                    if self.session.music.snapshot?.isPlaying != true {
                        self.level = 0
                    }
                }
            }
        }
    }

    func start() {
        guard !running else { return }
        running = true
        installProcessListener()
        session.music.$snapshot
            .map { $0?.isPlaying == true }
            .removeDuplicates()
            .sink { [weak self] playing in
                self?.handlePlayback(playing)
            }
            .store(in: &cancellables)
        attemptAttach()
    }

    private func handlePlayback(_ playing: Bool) {
        if playing {
            attemptAttach()
        } else {
            meter.reset()
            level = 0
            bars = Self.restBars
            if !session.music.musicIsRunning {
                teardownTap()
            }
        }
    }

    private func attemptAttach() {
        guard running else { return }
        if tapActive { return }
        if let musicID = Self.musicProcessObjectID() {
            attach(processObjectID: musicID)
        } else {
            lastError = "Music process object not in HAL list yet (app may be idle)."
            tapActive = false
        }
    }

    private func attach(processObjectID: AudioObjectID) {
        teardownTap()

        let description = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        description.name = "Halo Music Tap"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTap: AudioObjectID = 0
        let tapStatus = AudioHardwareCreateProcessTap(description, &newTap)
        guard tapStatus == noErr, newTap != 0 else {
            lastError = Self.describeTapFailure(tapStatus)
            tapActive = false
            NSLog("[Halo] Music process tap unavailable: %@", lastError ?? "unknown")
            return
        }
        tapID = newTap

        var tapUID: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let uidStatus = AudioObjectGetPropertyData(newTap, &uidAddress, 0, nil, &uidSize, &tapUID)
        guard uidStatus == noErr, let tapUIDString = tapUID?.takeUnretainedValue() as String? else {
            lastError = "Process tap created but UID could not be read (status \(uidStatus))."
            AudioHardwareDestroyProcessTap(newTap)
            tapID = 0
            tapActive = false
            return
        }

        guard let defaultUID = Self.defaultOutputUID() else {
            lastError = "No default output device UID; cannot build private aggregate around the tap."
            AudioHardwareDestroyProcessTap(newTap)
            tapID = 0
            tapActive = false
            return
        }

        let tapEntry: [String: Any] = [
            kAudioSubTapUIDKey: tapUIDString,
            kAudioSubTapDriftCompensationKey: true
        ]
        let subdevice: [String: Any] = [
            kAudioSubDeviceUIDKey: defaultUID
        ]
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Halo Music Tap Aggregate",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: defaultUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [subdevice],
            kAudioAggregateDeviceTapListKey: [tapEntry]
        ]

        var newAggregate: AudioObjectID = 0
        let aggStatus = AudioHardwareCreateAggregateDevice(composition as CFDictionary, &newAggregate)
        guard aggStatus == noErr, newAggregate != 0 else {
            lastError = "AudioHardwareCreateAggregateDevice failed (\(aggStatus)). Process tap cannot be read without an aggregate."
            AudioHardwareDestroyProcessTap(newTap)
            tapID = 0
            tapActive = false
            return
        }
        aggregateID = newAggregate

        let meter = self.meter
        var procID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, newAggregate, audioQueue) { _, inputData, _, outputData, _ in
            ProcessTapMeter.silence(outputData)
            meter.ingest(buffer: inputData)
        }
        guard ioStatus == noErr, let procID else {
            lastError = "AudioDeviceCreateIOProcIDWithBlock failed (\(ioStatus))."
            teardownTap()
            return
        }
        ioProcID = procID

        let startStatus = AudioDeviceStart(newAggregate, procID)
        guard startStatus == noErr else {
            lastError = "AudioDeviceStart on tap aggregate failed (\(startStatus)). TCC / Screen Recording may be denying capture."
            teardownTap()
            return
        }

        tapActive = true
        lastError = nil
        NSLog("[Halo] Music process tap started (tap %u, aggregate %u)", newTap, newAggregate)
    }

    private func teardownTap() {
        if let ioProcID, aggregateID != 0 {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        if aggregateID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = 0
        }
        if tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }
        tapActive = false
    }

    private func installProcessListener() {
        guard !processListenerInstalled else { return }
        processListenerInstalled = true
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.attemptAttach()
            }
        }
        if status != noErr {
            processListenerInstalled = false
        }
    }

    private static func musicProcessObjectID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var ids = Array(repeating: AudioObjectID(0), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &ids
        ) == noErr else { return nil }

        for id in ids {
            if stringProperty(id, kAudioProcessPropertyBundleID) == "com.apple.Music" {
                return id
            }
        }
        return nil
    }

    private static func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        var cf: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &cf)
        guard status == noErr, let cf else { return nil }
        return cf.takeUnretainedValue() as String
    }

    private static func defaultOutputUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        ) == noErr, device != 0 else { return nil }

        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        var uid: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, &uid) == noErr else { return nil }
        return uid?.takeUnretainedValue() as String?
    }

    private static func describeTapFailure(_ status: OSStatus) -> String {
        "AudioHardwareCreateProcessTap failed (\(status)). Public process-tap API is present, but capturing Music usually needs system audio capture / Screen Recording TCC. No MediaRemote. No public per-app meter fallback — bars stay at rest."
    }
}

final class ProcessTapMeter: @unchecked Sendable {
    var onPublish: ((Float, [Float]) -> Void)?

    private let lock = NSLock()
    private var envelope: Float = 0
    private var barEnvelopes = [Float](repeating: 0, count: 7)
    private var lastPublish: CFAbsoluteTime = 0

    private static let attack: Float = 0.030
    private static let release: Float = 0.200
    private static let barCount = 7

    func reset() {
        lock.lock()
        envelope = 0
        barEnvelopes = [Float](repeating: 0, count: Self.barCount)
        lock.unlock()
    }

    private static func smooth(_ value: inout Float, toward target: Float, dt: Float) {
        if target > value {
            value += (target - value) * min(1, dt / attack)
        } else {
            value += (target - value) * min(1, dt / release)
        }
        value = min(max(value, 0), 1)
    }

    func ingest(buffer list: UnsafePointer<AudioBufferList>) {
        let slices = Self.sliceLevels(list)
        let raw = slices.max() ?? 0
        let dt: Float = 1.0 / 48.0
        lock.lock()
        Self.smooth(&envelope, toward: raw, dt: dt)
        var bars = [Float](repeating: 0.06, count: Self.barCount)
        for i in 0..<min(slices.count, Self.barCount) {
            Self.smooth(&barEnvelopes[i], toward: slices[i], dt: dt)
            bars[i] = max(0.06, min(1, barEnvelopes[i]))
        }
        let level = envelope
        let now = CFAbsoluteTimeGetCurrent()
        let shouldPublish = now - lastPublish > 1.0 / 45.0
        if shouldPublish {
            lastPublish = now
        }
        lock.unlock()

        guard shouldPublish else { return }
        onPublish?(level, bars)
    }

    static func silence(_ outputData: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(outputData)
        for buffer in buffers {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }
    }

    static func sliceLevels(_ list: UnsafePointer<AudioBufferList>) -> [Float] {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard let first = buffers.first, let data = first.mData, first.mDataByteSize > 0 else {
            return Array(repeating: 0, count: barCount)
        }
        let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        guard count > barCount else { return Array(repeating: 0, count: barCount) }
        let pointer = data.assumingMemoryBound(to: Float.self)
        let slice = max(count / barCount, 1)
        var levels = [Float](repeating: 0, count: barCount)
        for i in 0..<barCount {
            let start = i * slice
            let length = i == barCount - 1 ? count - start : slice
            guard length > 0 else { continue }
            var meanSquare: Float = 0
            vDSP_measqv(pointer + start, 1, &meanSquare, vDSP_Length(length))
            levels[i] = min(1, sqrt(meanSquare) * 6)
        }
        return levels
    }
}
