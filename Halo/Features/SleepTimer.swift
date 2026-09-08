import Combine
import Foundation
import SwiftUI

@MainActor
final class SleepTimer: ObservableObject {
    unowned let session: AppSession
    @Published var remaining: TimeInterval = 0
    @Published var total: TimeInterval = 0
    @Published var isRunning = false

    private var endDate: Date?
    private var tickGeneration = 0
    private var fadeOriginVolume: Int?
    private var fading = false

    private static let fadeSeconds: TimeInterval = 20
    private static let coarseTick: TimeInterval = 1
    private static let fadeTick: TimeInterval = 0.1

    init(session: AppSession) {
        self.session = session
    }

    func start(minutes: Int) {
        guard session.settings.sleepTimer, minutes > 0 else { return }
        restoreVolumeIfFading()
        tickGeneration += 1
        total = TimeInterval(minutes * 60)
        remaining = total
        endDate = Date().addingTimeInterval(total)
        fading = false
        fadeOriginVolume = nil
        isRunning = true
        tick()
    }

    func cancel() {
        tickGeneration += 1
        restoreVolumeIfFading()
        endDate = nil
        remaining = 0
        total = 0
        fading = false
        isRunning = false
        session.island.clearTransient()
    }

    func tick() {
        tick(generation: tickGeneration)
    }

    private func tick(generation: Int) {
        guard generation == tickGeneration, let endDate else { return }
        remaining = max(endDate.timeIntervalSinceNow, 0)
        applyVolumeFadeIfNeeded()
        session.island.post(.sleepTimer(remaining: remaining, total: total), duration: nil)
        if remaining <= 0 {
            finish()
            return
        }
        let interval = remaining <= Self.fadeSeconds ? Self.fadeTick : Self.coarseTick
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.tick(generation: generation)
        }
    }

    private func applyVolumeFadeIfNeeded() {
        guard remaining <= Self.fadeSeconds else { return }
        if !fading {
            fading = true
            fadeOriginVolume = session.music.snapshot?.volume
        }
        let origin = fadeOriginVolume ?? session.music.snapshot?.volume ?? 100
        let fraction = remaining <= 0 ? 0 : min(max(remaining / Self.fadeSeconds, 0), 1)
        let volume = Int((Double(origin) * fraction).rounded())
        session.music.setVolume(max(0, min(100, volume)))
    }

    private func finish() {
        if session.music.snapshot?.isPlaying == true {
            session.music.playPause()
        }
        restoreVolumeIfFading()
        endDate = nil
        remaining = 0
        fading = false
        isRunning = false
        session.island.clearTransient()
    }

    private func restoreVolumeIfFading() {
        guard let fadeOriginVolume else { return }
        session.music.setVolume(fadeOriginVolume)
        self.fadeOriginVolume = nil
        fading = false
    }
}

struct SleepTimerView: View {
    var remaining: TimeInterval
    var total: TimeInterval
    @EnvironmentObject private var session: AppSession

    var body: some View {
        let progress = total == 0 ? 0 : remaining / total
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 22, height: 22)

                Text(timeString)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                session.sleepTimer.cancel()
            }

            if session.island.visualState == .expanded {
                SleepTimerPresets(compact: true)
            }
        }
    }

    private var timeString: String {
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct SleepTimerPresets: View {
    var compact: Bool = false
    @EnvironmentObject private var session: AppSession

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach([15, 30, 60], id: \.self) { minutes in
                let active = session.sleepTimer.isRunning
                    && Int(session.sleepTimer.total / 60) == minutes
                Button {
                    if active {
                        session.sleepTimer.cancel()
                    } else {
                        session.sleepTimer.start(minutes: minutes)
                    }
                } label: {
                    Text("\(minutes)m")
                        .font(.system(size: compact ? 9 : 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(active ? 1 : 0.72))
                        .padding(.horizontal, compact ? 6 : 8)
                        .padding(.vertical, compact ? 3 : 4)
                        .background(
                            Color.white.opacity(active ? 0.22 : 0.1),
                            in: Capsule(style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct RatingsQueueView: View {
    @EnvironmentObject private var session: AppSession
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                stars
                Spacer(minLength: 0)
                if session.settings.sleepTimer {
                    SleepTimerPresets()
                }
            }
            if hovering {
                queuePeek
            }
        }
        .onHover { hovering = $0 }
    }

    private var stars: some View {
        let rating = session.music.snapshot?.rating ?? 0
        return HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                let value = star * 20
                Button {
                    session.music.setRating(rating == value ? 0 : value)
                } label: {
                    Image(systemName: rating >= value ? "star.fill" : "star")
                        .foregroundStyle(rating >= value ? Color.yellow : Color.white.opacity(0.35))
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var queuePeek: some View {
        let tracks = Array((session.music.snapshot?.nextTracks ?? []).prefix(3))
        return VStack(alignment: .leading, spacing: 4) {
            if tracks.isEmpty {
                Text("Nothing next")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                ForEach(tracks) { track in
                    Text("\(track.title) — \(track.artist)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
        }
    }
}
