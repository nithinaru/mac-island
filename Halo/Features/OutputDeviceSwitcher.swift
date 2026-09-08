import CoreAudio
import Foundation
import SwiftUI

@MainActor
final class OutputDeviceSwitcher: ObservableObject {
    unowned let session: AppSession
    @Published var devices: [OutputDevice] = []

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        refresh()
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
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &id)
        refresh()
    }

    static func listDevices() -> [OutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = Array(repeating: AudioDeviceID(0), count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)

        var defaultID = AudioDeviceID(0)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, 0, nil, &defaultSize, &defaultID)

        return ids.compactMap { id in
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &nameAddress, 0, nil, &nameSize) == noErr else { return nil }
            var cf: Unmanaged<CFString>?
            guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &cf) == noErr, let cf else { return nil }
            return OutputDevice(id: id, name: cf.takeUnretainedValue() as String, isDefault: id == defaultID)
        }
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
