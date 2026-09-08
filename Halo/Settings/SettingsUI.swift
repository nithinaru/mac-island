import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct IslandContextMenu: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        Button("Settings…") { session.openSettings() }
        Button(session.settings.enforcementEnabled ? "Pause Enforcement" : "Resume Enforcement") {
            session.settings.enforcementEnabled.toggle()
        }
        Divider()
        Button("Quit Halo") { session.quit() }
    }
}

@MainActor
final class SettingsWindowController: NSObject, ObservableObject, NSWindowDelegate {
    unowned let session: AppSession
    private var window: NSWindow?

    init(session: AppSession) {
        self.session = session
        super.init()
    }

    func show() {
        if window == nil {
            let view = SettingsView().environmentObject(session)
            let hosting = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: hosting)
            win.title = "Halo Settings"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.setContentSize(NSSize(width: 460, height: 640))
            win.minSize = NSSize(width: 420, height: 420)
            win.isReleasedWhenClosed = false
            win.delegate = self
            window = win
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        SettingsForm(settings: session.settings)
            .environmentObject(session)
    }
}

struct SettingsForm: View {
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject private var session: AppSession
    @State private var newBundleID = ""

    var body: some View {
        Form {
            Section("Music exclusivity") {
                Toggle("Pause other audio apps", isOn: $settings.enforcementEnabled)
                Picker("Mode", selection: $settings.enforcementModeRaw) {
                    Text("Enforce").tag(EnforcementMode.enforce.rawValue)
                    Text("Display only").tag(EnforcementMode.displayOnly.rawValue)
                }
                Text("Safari and Chrome need Develop → Allow JavaScript from Apple Events once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Offender allowlist") {
                Text("These bundle IDs are never paused. Add Zoom, games, or anything else that should keep playing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(settings.allowlistEntries, id: \.self) { bundleID in
                    HStack {
                        Text(bundleID)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button("Remove", role: .destructive) {
                            settings.removeAllowlistEntry(bundleID)
                        }
                    }
                }
                HStack {
                    TextField("com.example.app", text: $newBundleID)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addTypedBundleID)
                    Button("Add") { addTypedBundleID() }
                        .disabled(newBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Choose App…") { chooseApplication() }
                }
            }
            Section("Features") {
                Toggle("Volume / brightness HUD", isOn: $settings.hudReplacement)
                Toggle("Screenshots", isOn: $settings.screenshots)
                Toggle("Clipboard ring", isOn: $settings.clipboard)
                Toggle("Live activities", isOn: $settings.liveActivities)
                Toggle("Charging ripple", isOn: $settings.charging)
                Toggle("Output switcher", isOn: $settings.outputSwitcher)
                Toggle("Mic privacy", isOn: $settings.privacy)
                Toggle("Downloads", isOn: $settings.downloads)
                Toggle("Focus arc", isOn: $settings.focus)
                Toggle("Meeting join", isOn: $settings.meetings)
                Toggle("Sleep timer", isOn: $settings.sleepTimer)
                Toggle("Menu bar item", isOn: $settings.menuBarItem)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                if !settings.launchAtLoginError.isEmpty {
                    Text(settings.launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section("Motion") {
                Slider(value: $settings.gooBlur, in: 6...24) { Text("Goo blur") }
                Slider(value: $settings.gooThreshold, in: 0.2...0.8) { Text("Goo threshold") }
                Slider(value: $settings.extraBounce, in: 0...0.3) { Text("Spring bounce") }
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.quaternary)
                    .frame(height: 44)
                    .overlay {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(.primary.opacity(0.85))
                                .frame(width: 18, height: 18)
                            Capsule(style: .continuous)
                                .fill(.primary.opacity(0.28))
                                .frame(height: 8)
                        }
                        .padding(.horizontal, 14)
                    }
                    .accessibilityLabel("Island shape preview")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 480)
        .onChange(of: settings.gooBlur) { _, _ in settings.syncMotionConstants() }
        .onChange(of: settings.gooThreshold) { _, _ in settings.syncMotionConstants() }
        .onChange(of: settings.extraBounce) { _, _ in settings.syncMotionConstants() }
        .onChange(of: settings.launchAtLogin) { _, value in
            session.loginItem.setEnabled(value)
        }
        .onChange(of: settings.hudReplacement) { _, value in
            if value {
                promptAccessibility()
                session.hud.installTap()
            }
        }
        .onChange(of: settings.menuBarItem) { _, _ in
            session.menuBar.start()
        }
    }

    private func addTypedBundleID() {
        settings.addAllowlistEntry(newBundleID)
        newBundleID = ""
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application, .applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Allowlist"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bundle = Bundle(url: url)
        let bundleID = bundle?.bundleIdentifier ?? Bundle(path: url.path)?.bundleIdentifier
        if let bundleID {
            settings.addAllowlistEntry(bundleID)
        }
    }

    private func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

@MainActor
final class MenuBarController: NSObject {
    unowned let session: AppSession
    private var item: NSStatusItem?

    init(session: AppSession) {
        self.session = session
        super.init()
    }

    func start() {
        if session.settings.menuBarItem {
            if item == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.title = "Halo"
                item.menu = makeMenu()
                self.item = item
            }
        } else {
            if let item {
                NSStatusBar.system.removeStatusItem(item)
                self.item = nil
            }
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let quitItem = NSMenuItem(title: "Quit Halo", action: #selector(quitHalo), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    @objc private func openSettings() {
        session.openSettings()
    }

    @objc private func quitHalo() {
        session.quit()
    }
}

@MainActor
final class LoginItemManager {
    unowned let session: AppSession
    private var isAligningToggle = false

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        if session.settings.launchAtLogin {
            setEnabled(true)
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard !isAligningToggle else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                switch SMAppService.mainApp.status {
                case .notRegistered, .notFound:
                    session.settings.launchAtLoginError = ""
                    return
                case .enabled, .requiresApproval:
                    try SMAppService.mainApp.unregister()
                @unknown default:
                    try SMAppService.mainApp.unregister()
                }
            }
            session.settings.launchAtLoginError = message(for: SMAppService.mainApp.status)
            alignToggle(desired: enabled)
        } catch {
            session.settings.launchAtLoginError = error.localizedDescription
            alignToggle(desired: enabled)
        }
    }

    private func alignToggle(desired: Bool) {
        let status = SMAppService.mainApp.status
        let isOn: Bool
        switch status {
        case .enabled, .requiresApproval:
            isOn = true
        case .notRegistered, .notFound:
            isOn = false
        @unknown default:
            isOn = desired
        }
        guard session.settings.launchAtLogin != isOn else { return }
        isAligningToggle = true
        session.settings.launchAtLogin = isOn
        DispatchQueue.main.async { [weak self] in
            self?.isAligningToggle = false
        }
    }

    private func message(for status: SMAppService.Status) -> String {
        switch status {
        case .enabled, .notRegistered:
            return ""
        case .requiresApproval:
            return "Halo is waiting for approval in System Settings → General → Login Items."
        case .notFound:
            return "The login item service was not found."
        @unknown default:
            return "Unexpected login item status."
        }
    }
}
