import SwiftUI

struct NowPlayingView: View {
    var namespace: Namespace.ID
    @EnvironmentObject private var session: AppSession

    var body: some View {
        let snapshot = session.music.snapshot
        let state = session.island.visualState
        HStack(spacing: 10) {
            art(snapshot)
                .matchedGeometryEffect(id: GeometryIDs.art, in: namespace)
            if state == .expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(snapshot?.title ?? "Not Playing")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .matchedGeometryEffect(id: GeometryIDs.title, in: namespace)
                    Text(snapshot?.artist ?? "")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                    WaveformSeekBar()
                    transport
                    if session.settings.ratings {
                        RatingsQueueView()
                    }
                }
            } else if state == .compact {
                CompactWaveformView()
                    .matchedGeometryEffect(id: GeometryIDs.waveform, in: namespace)
            }
        }
        .onAppear {
            if state == .expanded, session.music.snapshot?.isPlaying == true {
                session.music.startPositionPolling()
            }
        }
        .onDisappear {
            session.music.stopPositionPolling()
        }
    }

    @ViewBuilder
    private func art(_ snapshot: NowPlayingSnapshot?) -> some View {
        let side: CGFloat = session.island.visualState == .expanded ? 92 : 22
        ZStack {
            LinearGradient(
                colors: snapshot?.fallbackGradient ?? [.gray, .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let image = snapshot?.artwork {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.28, style: .continuous))
    }

    private var transport: some View {
        HStack(spacing: 18) {
            Button(action: session.music.previousTrack) {
                Image(systemName: "backward.fill")
            }
            Button(action: session.music.playPause) {
                Image(systemName: session.music.snapshot?.isPlaying == true ? "pause.fill" : "play.fill")
            }
            Button(action: session.music.nextTrack) {
                Image(systemName: "forward.fill")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .font(.system(size: 14, weight: .semibold))
    }
}
