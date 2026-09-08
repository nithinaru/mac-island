import AppKit
import ServiceManagement
import SwiftUI

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
final class SettingsWindowController: ObservableObject {
    unowned let session: AppSession
    private var window: NSWindow?

    init(session: AppSession) {
        self.session = session
    }

    func show() {
        if window == nil {
            let view = SettingsView().environmentObject(session)
            let hosting = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: hosting)
            win.title = "Halo Settings"
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.setContentSize(NSSize(width: 420, height: 560))
            win.isReleasedWhenClosed = false
            window = win
        }
        NSApp.setActivationPolicy(.accessory)
        window?.makeKeyAndOrderFront(nil)
        window?.level = .floating
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
                Toggle("Menu bar item", isOn: $settings.menuBarItem)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
            Section("Motion") {
                Slider(value: $settings.gooBlur, in: 6...24) { Text("Goo blur") }
                Slider(value: $settings.gooThreshold, in: 0.2...0.8) { Text("Goo threshold") }
                Slider(value: $settings.extraBounce, in: 0...0.3) { Text("Spring bounce") }
            }
        }
        .padding()
        .frame(width: 400)
        .onChange(of: settings.gooBlur) { _, _ in settings.syncMotionConstants() }
        .onChange(of: settings.gooThreshold) { _, _ in settings.syncMotionConstants() }
        .onChange(of: settings.extraBounce) { _, _ in settings.syncMotionConstants() }
        .onChange(of: settings.launchAtLogin) { _, value in
            session.loginItem.setEnabled(value)
        }
        .onChange(of: settings.hudReplacement) { _, value in
            if value { session.hud.installTap() }
        }
        .onChange(of: settings.menuBarItem) { _, _ in
            session.menuBar.start()
        }
    }
}

@MainActor
final class MenuBarController {
    unowned let session: AppSession
    private var item: NSStatusItem?

    init(session: AppSession) {
        self.session = session
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
        menu.addItem(withTitle: "Settings…", action: #selector(Dummy.open), keyEquivalent: ",")
        menu.addItem(withTitle: "Quit Halo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }
}

private final class Dummy: NSObject {
    @objc func open() {
        DispatchQueue.main.async {
            AppSession.shared.openSettings()
        }
    }
}

@MainActor
final class LoginItemManager {
    unowned let session: AppSession

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        if session.settings.launchAtLogin {
            setEnabled(true)
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            return
        }
    }
}
