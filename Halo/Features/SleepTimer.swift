import Combine
import Foundation
import SwiftUI

@MainActor
final class SleepTimer: ObservableObject {
    unowned let session: AppSession
    @Published var remaining: TimeInterval = 0
    @Published var total: TimeInterval = 0
    private var endDate: Date?

    init(session: AppSession) {
        self.session = session
    }

    func start(minutes: Int) {
        total = TimeInterval(minutes * 60)
        remaining = total
        endDate = Date().addingTimeInterval(total)
        tick()
    }

    func tick() {
        guard let endDate else { return }
        remaining = max(endDate.timeIntervalSinceNow, 0)
        session.island.post(.sleepTimer(remaining: remaining, total: total), duration: nil)
        if remaining <= 0 {
            session.music.playPause()
            self.endDate = nil
            session.island.clearTransient()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.tick()
        }
    }
}

struct SleepTimerView: View {
    var remaining: TimeInterval
    var total: TimeInterval

    var body: some View {
        let progress = total == 0 ? 0 : remaining / total
        HStack {
            Image(systemName: "moon.zzz.fill").foregroundStyle(.white)
            Text(timeString)
                .foregroundStyle(.white)
                .monospacedDigit()
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 16, height: 16)
        }
    }

    private var timeString: String {
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct RatingsQueueView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        session.music.setRating(star * 20)
                    } label: {
                        Image(systemName: (session.music.snapshot?.rating ?? 0) >= star * 20 ? "star.fill" : "star")
                            .foregroundStyle(.yellow)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(session.music.snapshot?.nextTracks ?? []) { track in
                Text("\(track.title) — \(track.artist)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
    }
}
