import AppKit
import Combine
import SwiftUI

@MainActor
final class AppSession: ObservableObject {
    static let shared = AppSession()

    let settings = SettingsStore()
    let geometry = ScreenGeometryStore()

    lazy var windows = NotchWindowManager(session: self)
    lazy var island = IslandController(session: self)
    lazy var music = MusicController(session: self)
    lazy var exclusivity = EnforcementEngine(session: self)
    lazy var waveform = WaveformAnalyzer(session: self)
    lazy var tempo = TempoAnalyzer(session: self)
    lazy var processTap = MusicProcessTap(session: self)
    lazy var hud = HUDController(session: self)
    lazy var screenshots = ScreenshotCatcher(session: self)
    lazy var clipboard = ClipboardRing(session: self)
    lazy var liveActivities = LiveActivityServer(session: self)
    lazy var charging = ChargingMonitor(session: self)
    lazy var outputs = OutputDeviceSwitcher(session: self)
    lazy var privacy = PrivacyMonitor(session: self)
    lazy var downloads = DownloadsMonitor(session: self)
    lazy var focus = FocusTimer(session: self)
    lazy var meetings = MeetingMonitor(session: self)
    lazy var sleepTimer = SleepTimer(session: self)
    lazy var mixer = AppMixerController(session: self)
    lazy var settingsWindow = SettingsWindowController(session: self)
    lazy var menuBar = MenuBarController(session: self)
    lazy var loginItem = LoginItemManager(session: self)

    private init() {}

    func start() {
        NSApp.setActivationPolicy(.accessory)
        geometry.refresh()
        settings.ensureBuiltInAllowlist()
        windows.start()
        island.start()
        music.start()
        exclusivity.start()
        waveform.start()
        tempo.start()
        processTap.start()
        hud.start()
        screenshots.start()
        clipboard.start()
        liveActivities.start()
        charging.start()
        outputs.start()
        privacy.start()
        downloads.start()
        meetings.start()
        mixer.start()
        settings.menuBarItem = true
        menuBar.start()
        loginItem.start()
        island.post(
            .liveActivity(
                LiveActivityPayload(
                    id: "halo.ready",
                    title: "Halo",
                    subtitle: "Hover the notch · Halo in the menu bar",
                    progress: nil,
                    symbol: "sparkles",
                    timeout: 5
                )
            ),
            duration: 5
        )
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func openSettings() {
        settingsWindow.show()
    }
}
