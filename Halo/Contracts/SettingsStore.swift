import Combine
import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @AppStorage("enforcementMode") var enforcementModeRaw: String = EnforcementMode.enforce.rawValue
    @AppStorage("enforcementEnabled") var enforcementEnabled: Bool = true
    @AppStorage("hudReplacement") var hudReplacement: Bool = false
    @AppStorage("screenshots") var screenshots: Bool = true
    @AppStorage("clipboard") var clipboard: Bool = true
    @AppStorage("liveActivities") var liveActivities: Bool = true
    @AppStorage("charging") var charging: Bool = true
    @AppStorage("outputSwitcher") var outputSwitcher: Bool = true
    @AppStorage("privacy") var privacy: Bool = true
    @AppStorage("downloads") var downloads: Bool = true
    @AppStorage("focus") var focus: Bool = true
    @AppStorage("meetings") var meetings: Bool = true
    @AppStorage("sleepTimer") var sleepTimer: Bool = true
    @AppStorage("ratings") var ratings: Bool = true
    @AppStorage("edgeScrubbing") var edgeScrubbing: Bool = true
    @AppStorage("bpmBreathing") var bpmBreathing: Bool = true
    @AppStorage("reactiveWaveform") var reactiveWaveform: Bool = true
    @AppStorage("menuBarItem") var menuBarItem: Bool = false
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("liveActivityPort") var liveActivityPort: Int = 18473
    @AppStorage("gooBlur") var gooBlur: Double = 14
    @AppStorage("gooThreshold") var gooThreshold: Double = 0.5
    @AppStorage("extraBounce") var extraBounce: Double = 0.14
    @AppStorage("allowlist") var allowlistRaw: String = SettingsStore.defaultAllowlist.joined(separator: ",")
    @AppStorage("launchAtLoginError") var launchAtLoginError: String = ""

    var enforcementMode: EnforcementMode {
        get { EnforcementMode(rawValue: enforcementModeRaw) ?? .enforce }
        set { enforcementModeRaw = newValue.rawValue }
    }

    var allowlist: Set<String> {
        get {
            Set(allowlistRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        }
        set {
            allowlistRaw = newValue.sorted().joined(separator: ",")
        }
    }

    var allowlistEntries: [String] {
        allowlist.sorted()
    }

    func addAllowlistEntry(_ bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var next = allowlist
        next.insert(trimmed)
        allowlist = next
    }

    func removeAllowlistEntry(_ bundleID: String) {
        var next = allowlist
        next.remove(bundleID)
        allowlist = next
    }

    func syncMotionConstants() {
        MotionConstants.gooBlur = gooBlur
        MotionConstants.gooThreshold = gooThreshold
        MotionConstants.extraBounce = extraBounce
    }

    static let defaultAllowlist: [String] = [
        "com.apple.controlcenter",
        "com.apple.audio.AudioMIDISetup",
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.apple.FaceTime",
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "com.apple.Music"
    ]
}
