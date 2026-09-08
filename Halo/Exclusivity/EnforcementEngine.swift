import AppKit
import Combine
import Foundation
import IOKit
import ScriptingBridge
import SwiftUI

@MainActor
final class EnforcementEngine: ObservableObject {
    unowned let session: AppSession
    let monitor = AudioProcessMonitor()
    @Published var lastAlert: ExclusivityAlert?
    @Published var browserPermissionNeeded: String?

    private var debounceTask: Task<Void, Never>?
    private var loginHold = true
    private var cancellables = Set<AnyCancellable>()
    private var surrendered = Set<String>()
    private var handling = false
    private let musicBundle = "com.apple.Music"
    private let debounceNanos: UInt64 = 400_000_000
    private let settleNanos: UInt64 = 450_000_000

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        monitor.$processes
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleEvaluate()
            }
            .store(in: &cancellables)

        monitor.start()

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self else { return }
            self.loginHold = false
            self.scheduleEvaluate()
        }
    }

    func evaluate() {
        guard session.settings.enforcementEnabled else { return }
        guard !loginHold else { return }
        guard !handling else { return }

        monitor.refresh()
        pruneSurrendered()

        let offenders = currentOffenders()
        guard !offenders.isEmpty else { return }
        guard session.settings.enforcementMode == .enforce else { return }

        handling = true
        Task { [weak self] in
            await self?.handle(offenders: offenders)
            self?.handling = false
        }
    }

    func pauseEnforcement() {
        session.settings.enforcementEnabled = false
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func scheduleEvaluate() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.debounceNanos ?? 400_000_000)
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }

    private func currentOffenders() -> [AudioApp] {
        let allowlist = session.settings.allowlist
        return monitor.outputting.filter { app in
            app.bundleID != musicBundle
                && !allowlist.contains(app.bundleID)
                && !surrendered.contains(app.bundleID)
                && app.bundleID != Bundle.main.bundleIdentifier
        }
    }

    private func pruneSurrendered() {
        let outputtingIDs = Set(monitor.outputting.map(\.bundleID))
        surrendered = surrendered.intersection(outputtingIDs)
    }

    private func handle(offenders: [AudioApp]) async {
        guard session.settings.enforcementEnabled, !loginHold else { return }
        guard session.settings.enforcementMode == .enforce else { return }

        monitor.refresh()
        pruneSurrendered()
        let stillOffending = currentOffenders().filter { candidate in
            offenders.contains { $0.bundleID == candidate.bundleID }
        }
        guard !stillOffending.isEmpty else { return }

        for app in stillOffending {
            switch OffenderLevers.pause(app) {
            case .attempted:
                break
            case .browserPermission(let message):
                browserPermissionNeeded = message
            }
        }

        try? await Task.sleep(nanoseconds: settleNanos)
        guard session.settings.enforcementEnabled else { return }

        monitor.refresh()
        pruneSurrendered()

        for app in stillOffending {
            guard monitor.outputting.contains(where: { $0.bundleID == app.bundleID }) else { continue }
            if OffenderLevers.isBrowser(app.bundleID) {
                OffenderLevers.postPlayPauseKey()
            } else if app.bundleID == "com.spotify.client" {
                OffenderLevers.postPlayPauseKey()
            }
        }

        try? await Task.sleep(nanoseconds: settleNanos)
        guard session.settings.enforcementEnabled else { return }

        monitor.refresh()
        for app in stillOffending {
            guard monitor.outputting.contains(where: { $0.bundleID == app.bundleID }) else { continue }
            surrendered.insert(app.bundleID)
            let alert = ExclusivityAlert(
                bundleID: app.bundleID,
                name: app.name,
                message: "\(app.name) is still playing audio. Bring it forward to pause it."
            )
            lastAlert = alert
            session.island.post(.exclusivity(alert))
        }
    }
}

enum PauseResult {
    case attempted
    case browserPermission(String)
}

enum OffenderLevers {
    @discardableResult
    static func pause(_ app: AudioApp) -> PauseResult {
        switch app.bundleID {
        case "com.spotify.client":
            pauseSpotify()
            return .attempted
        case "com.apple.Safari":
            return pauseSafari()
        case "com.google.Chrome",
             "company.thebrowser.Browser",
             "com.brave.Browser",
             "com.microsoft.edgemac":
            return pauseChromium(bundleID: app.bundleID)
        default:
            postPlayPauseKey()
            return .attempted
        }
    }

    static func isBrowser(_ bundleID: String) -> Bool {
        switch bundleID {
        case "com.apple.Safari",
             "com.google.Chrome",
             "company.thebrowser.Browser",
             "com.brave.Browser",
             "com.microsoft.edgemac":
            return true
        default:
            return false
        }
    }

    static func pauseSpotify() {
        guard isRunning("com.spotify.client") else { return }
        if let app = SBApplication(bundleIdentifier: "com.spotify.client") {
            let selector = NSSelectorFromString("pause")
            if app.responds(to: selector) {
                app.perform(selector)
                return
            }
        }
        _ = runAppleScript("tell application id \"com.spotify.client\" to pause")
    }

    @discardableResult
    static func pauseSafari() -> PauseResult {
        guard isRunning("com.apple.Safari") else { return .attempted }
        let script = """
        tell application "Safari"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        do JavaScript "document.querySelectorAll('video,audio').forEach(function(e){e.pause()})" in t
                    on error errMsg number errNum
                        if errMsg contains "Apple Events" or errMsg contains "JavaScript from Apple" or errNum is -1743 then
                            error errMsg number errNum
                        end if
                    end try
                end repeat
            end repeat
        end tell
        """
        if let error = runAppleScript(script) {
            if isJavaScriptPermissionError(error) {
                return .browserPermission(safariPermissionSteps)
            }
        }
        return .attempted
    }

    @discardableResult
    static func pauseChromium(bundleID: String) -> PauseResult {
        guard isRunning(bundleID) else { return .attempted }
        let script = """
        tell application id "\(bundleID)"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        execute t javascript "document.querySelectorAll('video,audio').forEach(function(e){e.pause()})"
                    on error errMsg number errNum
                        if errMsg contains "Apple Events" or errMsg contains "JavaScript from Apple" or errNum is -1743 then
                            error errMsg number errNum
                        end if
                    end try
                end repeat
            end repeat
        end tell
        """
        if let error = runAppleScript(script) {
            if isJavaScriptPermissionError(error) {
                return .browserPermission(chromiumPermissionSteps(bundleID: bundleID))
            }
        }
        return .attempted
    }

    static func postPlayPauseKey() {
        let key = Int64(NX_KEYTYPE_PLAY)
        postSystemDefinedKey(key, down: true)
        postSystemDefinedKey(key, down: false)
    }

    private static func postSystemDefinedKey(_ key: Int64, down: Bool) {
        let state: Int64 = down ? 0xA : 0xB
        let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((key << 16) | (state << 8)),
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }

    @discardableResult
    static func runAppleScript(_ source: String) -> AppleScriptFailure? {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        _ = script?.executeAndReturnError(&error)
        guard let error else { return nil }
        let message = (error[NSAppleScript.errorMessage] as? String) ?? ""
        let number = error[NSAppleScript.errorNumber] as? Int
        return AppleScriptFailure(message: message, number: number)
    }

    private static func isRunning(_ bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    private static func isJavaScriptPermissionError(_ error: AppleScriptFailure) -> Bool {
        let message = error.message.lowercased()
        if message.contains("apple events") || message.contains("javascript from apple") {
            return true
        }
        if error.number == -1743 || error.number == -1713 {
            return true
        }
        return false
    }

    static let safariPermissionSteps = """
    Safari blocked JavaScript from Apple Events. Enable it once: Safari → Develop → Allow JavaScript from Apple Events. If the Develop menu is hidden: Safari → Settings → Advanced → Show features for web developers.
    """

    static func chromiumPermissionSteps(bundleID: String) -> String {
        let appName: String
        switch bundleID {
        case "com.google.Chrome":
            appName = "Chrome"
        case "company.thebrowser.Browser":
            appName = "Arc"
        case "com.brave.Browser":
            appName = "Brave"
        case "com.microsoft.edgemac":
            appName = "Edge"
        default:
            appName = "Chrome"
        }
        return """
        \(appName) blocked JavaScript from Apple Events. Enable it once: View → Developer → Allow JavaScript from Apple Events. If Developer is missing, enable it in \(appName)’s settings, then retry.
        """
    }
}

struct AppleScriptFailure {
    var message: String
    var number: Int?
}

struct ExclusivityAlertView: View {
    var alert: ExclusivityAlert

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.slash.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text(alert.message)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(3)
            }
            Spacer(minLength: 8)
            Button("Bring to Front") {
                bringToFront(bundleID: alert.bundleID)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white)
    }

    private func bringToFront(bundleID: String) {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            running.activate()
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
