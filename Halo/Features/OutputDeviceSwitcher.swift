import CoreAudio
import Foundation
import SwiftUI

@MainActor
final class OutputDeviceSwitcher: ObservableObject {
    unowned let session: AppSession
    @Published var devices: [OutputDevice] = []
    private var listening = false

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        guard session.settings.outputSwitcher else { return }
        refresh()
        installListeners()
    }

    func refresh() {
        devices = Self.listDevices()
    }

    func select(_ device: OutputDevice) {
        var id = AudioDeviceID(device.id)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &id
        )
        if status != noErr {
            return
        }
        refresh()
    }

    static func listDevices() -> [OutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        guard sizeStatus == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var ids = Array(repeating: AudioDeviceID(0), count: count)
        let listStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &ids
        )
        guard listStatus == noErr else { return [] }

        var defaultID = AudioDeviceID(0)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            0,
            nil,
            &defaultSize,
            &defaultID
        )

        return ids.compactMap { id in
            guard hasOutputStreams(id) else { return nil }
            guard let name = deviceName(id), !name.isEmpty else { return nil }
            return OutputDevice(id: id, name: name, isDefault: id == defaultID)
        }
    }

    private func installListeners() {
        guard !listening else { return }
        listening = true
        let object = AudioObjectID(kAudioObjectSystemObject)
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let queue = DispatchQueue.main
        AudioObjectAddPropertyListenerBlock(object, &devicesAddress, queue) { [weak self] _, _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        AudioObjectAddPropertyListenerBlock(object, &defaultAddress, queue) { [weak self] _, _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
        return status == noErr && size > 0
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nameSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &nameAddress, 0, nil, &nameSize) == noErr else { return nil }
        var cf: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &cf) == noErr, let cf else { return nil }
        return cf.takeUnretainedValue() as String
    }
}

struct OutputDeviceView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(session.outputs.devices) { device in
                Button {
                    session.outputs.select(device)
                } label: {
                    HStack {
                        Text(device.name)
                        Spacer()
                        if device.isDefault {
                            Image(systemName: "checkmark")
                        }
                    }
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { session.outputs.refresh() }
    }
}
