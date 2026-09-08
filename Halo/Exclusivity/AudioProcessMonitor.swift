import AppKit
import CoreAudio
import Foundation

@MainActor
final class AudioProcessMonitor: ObservableObject {
    @Published var processes: [AudioApp] = []

    private var listenersInstalled = false
    private var listenedProcessIDs: Set<AudioObjectID> = []
    private let callbackQueue = DispatchQueue(label: "halo.audio-process-monitor")

    private lazy var listListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.handleHardwareChange()
    }

    private lazy var runningListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.handleHardwareChange()
    }

    func start() {
        refresh()
        installListener()
    }

    func refresh() {
        let snapshot = Self.currentProcesses()
        syncProcessListeners(ids: snapshot.objectIDs)
        if processes != snapshot.apps {
            processes = snapshot.apps
        }
    }

    var outputting: [AudioApp] {
        processes.filter(\.isOutput)
    }

    var inputting: [AudioApp] {
        processes.filter(\.isInput)
    }

    private func handleHardwareChange() {
        Task { @MainActor in
            self.refresh()
        }
    }

    private func installListener() {
        guard !listenersInstalled else { return }

        var listAddress = Self.listAddress
        let listStatus = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &listAddress,
            callbackQueue,
            listListener
        )
        guard listStatus == noErr else { return }

        var restartAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyServiceRestarted,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        _ = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &restartAddress,
            callbackQueue,
            listListener
        )

        listenersInstalled = true
        syncProcessListeners(ids: Self.processObjectIDs())
    }

    private func syncProcessListeners(ids: [AudioObjectID]) {
        let next = Set(ids)
        for id in listenedProcessIDs.subtracting(next) {
            removeRunningListeners(id)
        }
        for id in next.subtracting(listenedProcessIDs) {
            addRunningListeners(id)
        }
        listenedProcessIDs = next
    }

    private func addRunningListeners(_ id: AudioObjectID) {
        var output = Self.runningOutputAddress
        _ = AudioObjectAddPropertyListenerBlock(id, &output, callbackQueue, runningListener)
        var input = Self.runningInputAddress
        _ = AudioObjectAddPropertyListenerBlock(id, &input, callbackQueue, runningListener)
    }

    private func removeRunningListeners(_ id: AudioObjectID) {
        var output = Self.runningOutputAddress
        _ = AudioObjectRemovePropertyListenerBlock(id, &output, callbackQueue, runningListener)
        var input = Self.runningInputAddress
        _ = AudioObjectRemovePropertyListenerBlock(id, &input, callbackQueue, runningListener)
    }

    static func currentProcesses() -> (apps: [AudioApp], objectIDs: [AudioObjectID]) {
        let ids = processObjectIDs()
        let selfPID = ProcessInfo.processInfo.processIdentifier
        var merged: [String: AudioApp] = [:]

        for id in ids {
            if let pid = pidProperty(id), pid == selfPID {
                continue
            }
            guard let bundleID = stringProperty(id, kAudioProcessPropertyBundleID), !bundleID.isEmpty else {
                continue
            }
            let output = boolProperty(id, kAudioProcessPropertyIsRunningOutput)
            let input = boolProperty(id, kAudioProcessPropertyIsRunningInput)
            let name = Bundle.mainName(forBundleID: bundleID) ?? bundleID
            if var existing = merged[bundleID] {
                existing.isOutput = existing.isOutput || output
                existing.isInput = existing.isInput || input
                merged[bundleID] = existing
            } else {
                merged[bundleID] = AudioApp(
                    bundleID: bundleID,
                    name: name,
                    isOutput: output,
                    isInput: input
                )
            }
        }

        let apps = merged.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (apps, ids)
    }

    private static func processObjectIDs() -> [AudioObjectID] {
        var address = listAddress
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else { return [] }

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

        return ids.filter { $0 != 0 && $0 != kAudioObjectUnknown }
    }

    private static var listAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var runningOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var runningInputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
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
        return cf.takeRetainedValue() as String
    }

    private static func boolProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        uint32Property(id, selector).map { $0 != 0 } ?? false
    }

    private static func uint32Property(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<UInt32>.size)
        var value: UInt32 = 0
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value
    }

    private static func pidProperty(_ id: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<pid_t>.size)
        var value: pid_t = 0
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value
    }
}

extension Bundle {
    static func mainName(forBundleID id: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            .flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleName") as? String }
    }
}
