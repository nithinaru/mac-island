import AppKit
import Combine
import SwiftUI

@MainActor
final class MusicController: ObservableObject {
    unowned let session: AppSession
    @Published var snapshot: NowPlayingSnapshot?
    @Published var position: TimeInterval = 0

    private var positionTimer: Timer?

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.handlePlayerInfo(note)
            }
        }
        refreshFromNotification(userInfo: nil)
    }

    var musicIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Music" }
    }

    func playPause() {}
    func nextTrack() {}
    func previousTrack() {}
    func seek(to seconds: TimeInterval) {}
    func setVolume(_ value: Int) {}
    func setRating(_ rating: Int) {}

    func startPositionPolling() {
        stopPositionPolling()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPosition()
            }
        }
    }

    func stopPositionPolling() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func pollPosition() {}

    private func handlePlayerInfo(_ note: Notification) {
        refreshFromNotification(userInfo: note.userInfo as? [String: Any])
        session.island.recomputeState()
    }

    private func refreshFromNotification(userInfo: [String: Any]?) {}
}
