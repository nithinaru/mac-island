import SwiftUI

struct NowPlayingView: View {
    var namespace: Namespace.ID
    @EnvironmentObject private var session: AppSession

    var body: some View {
        let snapshot = session.music.snapshot
        let state = session.island.visualState
        let notchWidth = session.geometry.metrics.idleSize.width
        Group {
            if state == .expanded {
                expanded(snapshot)
            } else {
                CompactWingLayout(notchWidth: notchWidth) {
                    art(snapshot, side: 18)
                        .matchedGeometryEffect(id: GeometryIDs.art, in: namespace)
                } right: {
                    CompactWaveformView()
                        .matchedGeometryEffect(id: GeometryIDs.waveform, in: namespace)
                }
            }
        }
        .animation(.easeInOut(duration: MotionConstants.colorBleedDuration), value: snapshot?.persistentID)
        .onAppear(perform: syncPolling)
        .onDisappear {
            session.music.stopPositionPolling()
        }
        .onChange(of: session.island.visualState) { _, _ in
            syncPolling()
        }
        .onChange(of: session.music.snapshot?.isPlaying) { _, _ in
            syncPolling()
        }
    }

    private func expanded(_ snapshot: NowPlayingSnapshot?) -> some View {
        HStack(spacing: 12) {
            art(snapshot, side: 64)
                .matchedGeometryEffect(id: GeometryIDs.art, in: namespace)
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot?.title ?? "Not Playing")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .matchedGeometryEffect(id: GeometryIDs.title, in: namespace)
                Text(snapshot?.artist ?? "")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                WaveformSeekBar()
                    .matchedGeometryEffect(id: GeometryIDs.waveform, in: namespace)
                transport
            }
        }
    }

    @ViewBuilder
    private func art(_ snapshot: NowPlayingSnapshot?, side: CGFloat) -> some View {
        let colors = snapshot?.fallbackGradient ?? ArtworkFallback.gradient(artist: "", album: "idle")
        ZStack {
            LinearGradient(
                colors: colors,
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
        HStack(spacing: 16) {
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
        .font(.system(size: 13, weight: .semibold))
    }

    private func syncPolling() {
        if session.island.visualState == .expanded, session.music.snapshot?.isPlaying == true {
            session.music.startPositionPolling()
        } else {
            session.music.stopPositionPolling()
        }
    }
}
