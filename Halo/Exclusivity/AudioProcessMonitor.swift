import AppKit
import CoreAudio
import Foundation

@MainActor
final class AudioProcessMonitor: ObservableObject {
    @Published var processes: [AudioApp] = []
    private var listenersInstalled = false

    func start() {
        refresh()
        installListener()
    }

    func refresh() {
        processes = Self.currentProcesses()
    }

    var outputting: [AudioApp] {
        processes.filter(\.isOutput)
    }

    var inputting: [AudioApp] {
        processes.filter(\.isInput)
    }

    private func installListener() {
        guard !listenersInstalled else { return }
        listenersInstalled = true
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
                self?.refresh()
            }
        }
        if status != noErr {
            listenersInstalled = false
        }
    }

    static func currentProcesses() -> [AudioApp] {
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
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var ids = Array(repeating: AudioObjectID(0), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &ids
        ) == noErr else { return [] }

        return ids.compactMap { id in
            guard let bundleID = stringProperty(id, kAudioProcessPropertyBundleID) else { return nil }
            let output = boolProperty(id, kAudioProcessPropertyIsRunningOutput)
            let input = boolProperty(id, kAudioProcessPropertyIsRunningInput)
            let name = Bundle.mainName(forBundleID: bundleID) ?? bundleID
            return AudioApp(bundleID: bundleID, name: name, isOutput: output, isInput: input)
        }
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

    private static func boolProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<UInt32>.size)
        var value: UInt32 = 0
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return status == noErr && value != 0
    }
}

extension Bundle {
    static func mainName(forBundleID id: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            .flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleName") as? String }
    }
}
