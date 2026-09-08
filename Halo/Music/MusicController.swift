import AppKit
import Combine
import ScriptingBridge
import SwiftUI

/// ScriptingBridge proxies are dynamic; the generated `Music.h` classes have no
/// implementation objects to link. These protocols are the public Music suite.
@objc private protocol HaloMusicApplication: NSObjectProtocol {
    var currentTrack: AnyObject { get }
    var currentPlaylist: AnyObject { get }
    var playerPosition: Double { get set }
    var playerState: MusicEPlS { get }
    var soundVolume: Int { get set }
    func playpause()
    func nextTrack()
    func previousTrack()
}

@objc private protocol HaloMusicTrack: NSObjectProtocol {
    var name: String { get }
    var artist: String { get }
    var album: String { get }
    var persistentID: String { get }
    var duration: Double { get }
    var rating: Int { get set }
    var playedCount: Int { get }
    var bpm: Int { get }
    var index: Int { get }
    func artworks() -> SBElementArray
}

@objc private protocol HaloMusicPlaylist: NSObjectProtocol {
    func tracks() -> SBElementArray
}

@objc private protocol HaloMusicArtwork: NSObjectProtocol {
    var data: NSImage { get }
    var rawData: Any { get }
}

@MainActor
final class MusicController: ObservableObject {
    unowned let session: AppSession
    @Published var snapshot: NowPlayingSnapshot?
    @Published var position: TimeInterval = 0

    private var positionTimer: Timer?
    private var playerInfoObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var cachedArtworkID: String?
    private var cachedArtwork: NSImage?

    /// ScriptingBridge properties that failed or are unavailable on the public Music suite:
    /// - `MusicTrack.location` is not on the base track class (only file/CD subclasses). Generic `currentTrack` is typically a `MusicTrack` proxy, so location is read with KVC. Nil means no public file URL — we do not use private APIs.
    /// - There is no “Up Next” queue in ScriptingBridge. Next three tracks come from `currentPlaylist.tracks` after `currentTrack.index` (playlist order, not shuffle play order).
    /// - Generated `MusicApplication` / `MusicTrack` ObjC classes from `Music.h` do not exist at link time; the running objects are ScriptingBridge proxies addressed via the protocols above.
    init(session: AppSession) {
        self.session = session
    }

    func start() {
        if playerInfoObserver == nil {
            playerInfoObserver = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.Music.playerInfo"),
                object: nil,
                queue: .main
            ) { [weak self] note in
                Task { @MainActor in
                    self?.handlePlayerInfo(note)
                }
            }
        }

        session.island.$visualState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncPositionPolling()
            }
            .store(in: &cancellables)

        refreshFromNotification(userInfo: nil)
        session.island.recomputeState()
        syncPositionPolling()
    }

    var musicIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Music" }
    }

    func playPause() {
        withMusic { $0.playpause() }
    }

    func nextTrack() {
        withMusic { $0.nextTrack() }
    }

    func previousTrack() {
        withMusic { $0.previousTrack() }
    }

    func seek(to seconds: TimeInterval) {
        withMusic { music in
            music.playerPosition = max(seconds, 0)
            position = music.playerPosition
            snapshot?.position = position
        }
    }

    func setVolume(_ value: Int) {
        withMusic { music in
            music.soundVolume = min(max(value, 0), 100)
            snapshot?.volume = Int(music.soundVolume)
        }
    }

    func setRating(_ rating: Int) {
        withMusic { music in
            guard let track = validTrack(music.currentTrack) else { return }
            track.rating = min(max(rating, 0), 100)
            snapshot?.rating = Int(track.rating)
        }
    }

    func startPositionPolling() {
        stopPositionPolling()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPosition()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        positionTimer = timer
        pollPosition()
    }

    func stopPositionPolling() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    private func syncPositionPolling() {
        let shouldPoll = snapshot?.isPlaying == true && session.island.visualState == .expanded
        if shouldPoll {
            if positionTimer == nil {
                startPositionPolling()
            }
        } else {
            stopPositionPolling()
        }
    }

    private func pollPosition() {
        guard snapshot?.isPlaying == true, session.island.visualState == .expanded else {
            stopPositionPolling()
            return
        }
        guard musicIsRunning else {
            stopPositionPolling()
            return
        }
        withMusic { music in
            let seconds = music.playerPosition
            guard seconds.isFinite else { return }
            position = seconds
            snapshot?.position = seconds
        }
    }

    private func handlePlayerInfo(_ note: Notification) {
        refreshFromNotification(userInfo: note.userInfo as? [String: Any])
        session.island.recomputeState()
        syncPositionPolling()
    }

    private func refreshFromNotification(userInfo: [String: Any]?) {
        guard musicIsRunning else {
            clearSnapshot()
            return
        }
        guard let music = musicApp() else {
            clearSnapshot()
            return
        }

        let playerStateText = stringValue(userInfo?["Player State"])
        let isPlaying: Bool
        if playerStateText.isEmpty {
            switch music.playerState {
            case MusicEPlSPlaying, MusicEPlSFastForwarding, MusicEPlSRewinding:
                isPlaying = true
            case MusicEPlSPaused, MusicEPlSStopped:
                isPlaying = false
            default:
                isPlaying = false
            }
        } else {
            switch playerStateText {
            case "Playing", "Fast Forwarding", "Rewinding":
                isPlaying = true
            default:
                isPlaying = false
            }
        }

        if playerStateText == "Stopped" {
            if validTrack(music.currentTrack) == nil {
                clearSnapshot()
                return
            }
        }

        let track = validTrack(music.currentTrack)
        let title = firstNonEmpty(stringValue(userInfo?["Name"]), track?.name)
        let artist = firstNonEmpty(stringValue(userInfo?["Artist"]), track?.artist)
        let album = firstNonEmpty(stringValue(userInfo?["Album"]), track?.album)
        let persistentID = firstNonEmpty(stringValue(userInfo?["PersistentID"]), track?.persistentID)

        if title.isEmpty && persistentID.isEmpty && track == nil {
            snapshot = nil
            position = 0
            return
        }

        let duration: TimeInterval = {
            if let track, track.duration > 0 { return track.duration }
            if let total = numberValue(userInfo?["Total Time"]) {
                return total > 10_000 ? total / 1000 : total
            }
            return snapshot?.duration ?? 0
        }()

        var currentPosition = position
        if isPlaying || session.island.visualState == .expanded {
            let sbPosition = music.playerPosition
            if sbPosition.isFinite {
                currentPosition = max(sbPosition, 0)
            }
        }
        position = currentPosition

        let rating = track.map { Int($0.rating) } ?? snapshot?.rating ?? 0
        let playedCount = track.map { Int($0.playedCount) } ?? snapshot?.playedCount ?? 0
        let bpm = track.map { Int($0.bpm) } ?? snapshot?.bpm ?? 0
        let volume = Int(music.soundVolume)
        let fileURL = track.flatMap(fileURL(for:))
        let artwork = artworkImage(for: track, persistentID: persistentID)
        let fallbackGradient = ArtworkFallback.gradient(artist: artist, album: album)
        let gradientAccent = ArtworkFallback.accent(fromGradient: fallbackGradient)
        let accent = ColorBleed.accent(from: artwork, fallback: gradientAccent)
        let nextTracks = track.map { peekNextTracks(music: music, current: $0) } ?? []

        snapshot = NowPlayingSnapshot(
            persistentID: persistentID,
            title: title.isEmpty ? "Unknown Track" : title,
            artist: artist,
            album: album,
            duration: duration,
            position: currentPosition,
            isPlaying: isPlaying,
            rating: rating,
            playedCount: playedCount,
            bpm: bpm,
            volume: volume,
            fileURL: fileURL,
            artwork: artwork,
            fallbackGradient: fallbackGradient,
            accent: accent,
            nextTracks: nextTracks
        )

        if isPlaying {
            session.waveform.analyze(fileURL: fileURL, persistentID: persistentID)
            session.tempo.update(taggedBPM: bpm, fileURL: fileURL, persistentID: persistentID)
        }
    }

    private func clearSnapshot() {
        snapshot = nil
        position = 0
        cachedArtwork = nil
        cachedArtworkID = nil
        stopPositionPolling()
    }

    private func artworkImage(for track: HaloMusicTrack?, persistentID: String) -> NSImage? {
        if !persistentID.isEmpty, cachedArtworkID == persistentID, let cachedArtwork {
            return cachedArtwork
        }
        guard let track else { return nil }
        let arts = track.artworks()
        guard arts.count > 0,
              let art: HaloMusicArtwork = asMusicProxy(arts.object(at: 0)) else {
            cachedArtwork = nil
            cachedArtworkID = persistentID
            return nil
        }
        if art.data.size.width > 0, art.data.size.height > 0 {
            cachedArtwork = art.data
            cachedArtworkID = persistentID
            return art.data
        }
        if let raw = art.rawData as? Data, let image = NSImage(data: raw), image.size.width > 0 {
            cachedArtwork = image
            cachedArtworkID = persistentID
            return image
        }
        cachedArtwork = nil
        cachedArtworkID = persistentID
        return nil
    }

    private func fileURL(for track: HaloMusicTrack) -> URL? {
        (track as AnyObject).value(forKey: "location") as? URL
    }

    private func peekNextTracks(music: HaloMusicApplication, current: HaloMusicTrack) -> [QueueTrack] {
        guard let playlist: HaloMusicPlaylist = asMusicProxy(music.currentPlaylist) else { return [] }
        let elements = playlist.tracks()
        let count = Int(elements.count)
        guard count > 0 else { return [] }

        var start = current.index
        if start <= 0 {
            let pid = current.persistentID
            if !pid.isEmpty {
                let limit = min(count, 400)
                for i in 0..<limit {
                    if let candidate: HaloMusicTrack = asMusicProxy(elements.object(at: i)),
                       candidate.persistentID == pid {
                        start = i + 1
                        break
                    }
                }
            }
        }
        guard start > 0 else { return [] }

        var result: [QueueTrack] = []
        var index = start + 1
        while result.count < 3, index <= count {
            if let track: HaloMusicTrack = asMusicProxy(elements.object(at: index - 1)) {
                let id = firstNonEmpty(track.persistentID, "\(index)")
                result.append(
                    QueueTrack(
                        id: id,
                        title: firstNonEmpty(track.name, "Track \(index)"),
                        artist: track.artist
                    )
                )
            }
            index += 1
        }
        return result
    }

    private func asMusicProxy<T>(_ object: Any?) -> T? {
        guard let object, !(object is NSNull) else { return nil }
        let typed: T = (object as AnyObject) as! T
        return typed
    }

    private func validTrack(_ raw: AnyObject?) -> HaloMusicTrack? {
        guard let track: HaloMusicTrack = asMusicProxy(raw) else { return nil }
        if track.persistentID.isEmpty && track.name.isEmpty { return nil }
        return track
    }

    private func musicApp() -> HaloMusicApplication? {
        guard musicIsRunning else { return nil }
        guard let sb = SBApplication(bundleIdentifier: "com.apple.Music") else { return nil }
        return asMusicProxy(sb)
    }

    @discardableResult
    private func withMusic(_ body: (HaloMusicApplication) -> Void) -> Bool {
        guard let music = musicApp() else { return false }
        body(music)
        return true
    }

    private func stringValue(_ raw: Any?) -> String {
        switch raw {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return ""
        }
    }

    private func numberValue(_ raw: Any?) -> Double? {
        switch raw {
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    private func firstNonEmpty(_ values: String?...) -> String {
        for value in values {
            if let value, !value.isEmpty, value != "<null>" { return value }
        }
        return ""
    }
}
