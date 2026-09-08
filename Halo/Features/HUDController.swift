import AppKit
import ApplicationServices
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import SwiftUI

@MainActor
final class HUDController: ObservableObject {
    unowned let session: AppSession
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private nonisolated(unsafe) var tapPort: CFMachPort?

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        guard session.settings.hudReplacement else { return }
        guard AXIsProcessTrusted() else { return }
        attachEventTap()
    }

    func installTap() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }
        attachEventTap()
    }

    private func attachEventTap() {
        removeTap()
        let mask = CGEventMask(1 << NSEvent.EventType.systemDefined.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
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
            userInfo: pointer
        ) else { return }
        self.tap = tap
        tapPort = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeTap() {
        if let source = tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        tap = nil
        tapPort = nil
        tapSource = nil
    }

    nonisolated func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tapPort {
                CGEvent.tapEnable(tap: tapPort, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard UserDefaults.standard.bool(forKey: "hudReplacement") else {
            return Unmanaged.passUnretained(event)
        }

        let systemDefined = CGEventType(rawValue: UInt32(NSEvent.EventType.systemDefined.rawValue))
        guard type == systemDefined, let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }
        guard nsEvent.subtype.rawValue == NX_SUBTYPE_AUX_CONTROL_BUTTONS else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = (nsEvent.data1 & 0xFFFF0000) >> 16
        let keyState = (nsEvent.data1 & 0x0000FF00) >> 8
        let isDown = keyState == NX_KEYSTATE_DOWN
        let isRepeat = keyState == NX_KEYSTATE_REPEAT

        guard isDown || isRepeat || keyState == NX_KEYSTATE_UP else {
            return Unmanaged.passUnretained(event)
        }

        switch keyCode {
        case NX_KEYTYPE_SOUND_UP:
            if isDown || isRepeat { applyVolume(delta: HUDAudio.step) }
            return nil
        case NX_KEYTYPE_SOUND_DOWN:
            if isDown || isRepeat { applyVolume(delta: -HUDAudio.step) }
            return nil
        case NX_KEYTYPE_MUTE:
            if isDown { applyVolume(toggleMute: true) }
            return nil
        case NX_KEYTYPE_BRIGHTNESS_UP, NX_KEYTYPE_BRIGHTNESS_DOWN:
            guard DisplayServicesBridge.isAvailable else {
                return Unmanaged.passUnretained(event)
            }
            if isDown || isRepeat {
                let delta: Float = keyCode == NX_KEYTYPE_BRIGHTNESS_UP ? HUDAudio.step : -HUDAudio.step
                if !applyBrightness(delta: delta) {
                    return Unmanaged.passUnretained(event)
                }
            }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    nonisolated private func applyVolume(delta: Float = 0, toggleMute: Bool = false) {
        guard let device = HUDAudio.defaultOutputDevice() else { return }
        if toggleMute {
            let muted = HUDAudio.isMuted(device)
            HUDAudio.setMuted(device, !muted)
            let level = HUDAudio.volume(device)
            postVolume(level: level, muted: !muted)
            return
        }
        if delta > 0, HUDAudio.isMuted(device) {
            HUDAudio.setMuted(device, false)
        }
        let next = min(1, max(0, HUDAudio.volume(device) + delta))
        HUDAudio.setVolume(device, next)
        if next <= 0.001 {
            HUDAudio.setMuted(device, true)
        }
        postVolume(level: next, muted: next <= 0.001 || HUDAudio.isMuted(device))
    }

    nonisolated private func applyBrightness(delta: Float) -> Bool {
        guard DisplayServicesBridge.isAvailable else { return false }
        let display = DisplayServicesBridge.targetDisplay()
        let current = DisplayServicesBridge.brightness(display) ?? 0.5
        let next = min(1, max(0, current + delta))
        guard DisplayServicesBridge.setBrightness(display, next) else { return false }
        postBrightness(next)
        return true
    }

    nonisolated private func postVolume(level: Float, muted: Bool) {
        Task { @MainActor in
            self.session.island.post(.volume(level: muted ? 0 : level, muted: muted))
        }
    }

    nonisolated private func postBrightness(_ value: Float) {
        Task { @MainActor in
            self.setBrightness(value)
        }
    }

    func setVolumeScalar(_ value: Float) {
        session.island.post(.volume(level: value, muted: value <= 0.001))
    }

    func setBrightness(_ value: Float) {
        session.island.post(.brightness(value))
    }
}

private let NX_SUBTYPE_AUX_CONTROL_BUTTONS: Int16 = 8
private let NX_KEYSTATE_DOWN = 0x0A
private let NX_KEYSTATE_UP = 0x0B
private let NX_KEYSTATE_REPEAT = 0x01
private let NX_KEYTYPE_SOUND_UP = 0
private let NX_KEYTYPE_SOUND_DOWN = 1
private let NX_KEYTYPE_BRIGHTNESS_UP = 2
private let NX_KEYTYPE_BRIGHTNESS_DOWN = 3
private let NX_KEYTYPE_MUTE = 7

private enum HUDAudio {
    static let step: Float = 1.0 / 16.0

    static func defaultOutputDevice() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &id
        )
        return status == noErr && id != 0 ? id : nil
    }

    static func volume(_ device: AudioDeviceID) -> Float {
        let elements = volumeElements(device)
        var total: Float = 0
        var count: Float = 0
        for element in elements {
            if let value = scalar(device, selector: kAudioDevicePropertyVolumeScalar, element: element) {
                total += value
                count += 1
            }
        }
        return count > 0 ? total / count : 0
    }

    static func setVolume(_ device: AudioDeviceID, _ value: Float) {
        for element in volumeElements(device) {
            setScalar(device, selector: kAudioDevicePropertyVolumeScalar, element: element, value: value)
        }
    }

    static func isMuted(_ device: AudioDeviceID) -> Bool {
        let elements = muteElements(device)
        guard !elements.isEmpty else { return false }
        return elements.allSatisfy { element in
            (scalar(device, selector: kAudioDevicePropertyMute, element: element) ?? 0) > 0.5
        }
    }

    static func setMuted(_ device: AudioDeviceID, _ muted: Bool) {
        let value: UInt32 = muted ? 1 : 0
        for element in muteElements(device) {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            var payload = value
            let size = UInt32(MemoryLayout<UInt32>.size)
            _ = AudioObjectSetPropertyData(device, &address, 0, nil, size, &payload)
        }
    }

    private static func volumeElements(_ device: AudioDeviceID) -> [UInt32] {
        if hasProperty(device, selector: kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain) {
            return [kAudioObjectPropertyElementMain]
        }
        return [1, 2].filter { hasProperty(device, selector: kAudioDevicePropertyVolumeScalar, element: $0) }
    }

    private static func muteElements(_ device: AudioDeviceID) -> [UInt32] {
        if hasProperty(device, selector: kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain) {
            return [kAudioObjectPropertyElementMain]
        }
        return [1, 2].filter { hasProperty(device, selector: kAudioDevicePropertyMute, element: $0) }
    }

    private static func hasProperty(_ device: AudioDeviceID, selector: AudioObjectPropertySelector, element: UInt32) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        return AudioObjectHasProperty(device, &address)
    }

    private static func scalar(_ device: AudioDeviceID, selector: AudioObjectPropertySelector, element: UInt32) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        if selector == kAudioDevicePropertyMute {
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
            return status == noErr ? Float(value) : nil
        }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func setScalar(_ device: AudioDeviceID, selector: AudioObjectPropertySelector, element: UInt32, value: Float) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        var payload = Float32(value)
        let size = UInt32(MemoryLayout<Float32>.size)
        _ = AudioObjectSetPropertyData(device, &address, 0, nil, size, &payload)
    }
}

private enum DisplayServicesBridge {
    typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_LAZY
    )

    private static let getBrightnessSym: GetBrightness? = {
        guard let handle, let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: GetBrightness.self)
    }()

    private static let setBrightnessSym: SetBrightness? = {
        guard let handle, let symbol = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: SetBrightness.self)
    }()

    static var isAvailable: Bool { setBrightnessSym != nil }

    static func targetDisplay() -> CGDirectDisplayID {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = Array(repeating: CGDirectDisplayID(0), count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        if let builtin = displays.first(where: { CGDisplayIsBuiltin($0) != 0 }) {
            return builtin
        }
        return CGMainDisplayID()
    }

    static func brightness(_ display: CGDirectDisplayID) -> Float? {
        guard let getBrightnessSym else { return nil }
        var value: Float = 0
        return getBrightnessSym(display, &value) == 0 ? value : nil
    }

    static func setBrightness(_ display: CGDirectDisplayID, _ value: Float) -> Bool {
        guard let setBrightnessSym else { return false }
        return setBrightnessSym(display, value) == 0
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
