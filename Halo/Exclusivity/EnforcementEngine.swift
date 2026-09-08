import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class EnforcementEngine: ObservableObject {
    unowned let session: AppSession
    let monitor = AudioProcessMonitor()
    @Published var lastAlert: ExclusivityAlert?
    @Published var browserPermissionNeeded: String?

    private var debounceTask: Task<Void, Never>?
    private var loginHold = true
    private let musicBundle = "com.apple.Music"

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        monitor.start()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self?.loginHold = false
        }
        Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluate()
            }
        }
    }

    func evaluate() {
        guard session.settings.enforcementEnabled else { return }
        guard !loginHold else { return }
        monitor.refresh()
        let offenders = monitor.outputting.filter { app in
            app.bundleID != musicBundle && !session.settings.allowlist.contains(app.bundleID)
        }
        guard !offenders.isEmpty else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.handle(offenders: offenders)
            }
        }
    }

    private func handle(offenders: [AudioApp]) {
        guard session.settings.enforcementMode == .enforce else { return }
        for app in offenders {
            OffenderLevers.pause(app)
        }
    }

    func pauseEnforcement() {
        session.settings.enforcementEnabled = false
    }
}

enum OffenderLevers {
    static func pause(_ app: AudioApp) {
        switch app.bundleID {
        case "com.spotify.client":
            _ = runAppleScript("tell application id \"com.spotify.client\" to pause")
        case "com.apple.Safari":
            pauseSafari()
        case "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac":
            pauseChromium(bundleID: app.bundleID)
        default:
            postPlayPauseKey()
        }
    }

    static func pauseSafari() {
        let script = """
        tell application "Safari"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        do JavaScript "document.querySelectorAll('video,audio').forEach(e=>e.pause())" in t
                    end try
                end repeat
            end repeat
        end tell
        """
        _ = runAppleScript(script)
    }

    static func pauseChromium(bundleID: String) {
        let script = """
        tell application id "\(bundleID)"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        execute t javascript "document.querySelectorAll('video,audio').forEach(e=>e.pause())"
                    end try
                end repeat
            end repeat
        end tell
        """
        _ = runAppleScript(script)
    }

    static func postPlayPauseKey() {
        let key: Int64 = 16
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        down?.setIntegerValueField(.keyboardEventKeycode, value: 0)
        let flags = NX_KEYTYPE_PLAY
        _ = flags
        let sysDown = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((key << 16) | (0xA << 8)),
            data2: -1
        )
        sysDown?.cgEvent?.post(tap: .cghidEventTap)
        let sysUp = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xB00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((key << 16) | (0xB << 8)),
            data2: -1
        )
        sysUp?.cgEvent?.post(tap: .cghidEventTap)
    }

    @discardableResult
    static func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        let output = script?.executeAndReturnError(&error)
        return output?.stringValue
    }
}

struct ExclusivityAlertView: View {
    var alert: ExclusivityAlert

    var body: some View {
        HStack {
            Image(systemName: "speaker.slash.fill")
            VStack(alignment: .leading) {
                Text(alert.name).foregroundStyle(.white)
                Text(alert.message).foregroundStyle(.white.opacity(0.6)).font(.caption)
            }
            Button("Bring Forward") {
                NSWorkspace.shared.launchApplication(withBundleIdentifier: alert.bundleID, options: [], additionalEventParamDescriptor: nil, launchIdentifier: nil)
            }
        }
        .foregroundStyle(.white)
    }
}
