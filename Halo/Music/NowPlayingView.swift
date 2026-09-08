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
                        .matchedGeometryEffect(id: GeometryIDs.waveform, in: namespace)
                    transport
                    if session.settings.ratings {
                        RatingsQueueView()
                    }
                }
            } else if state == .compact {
                Text(snapshot?.title ?? "")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .matchedGeometryEffect(id: GeometryIDs.title, in: namespace)
                    .accessibilityHidden(true)
                CompactWaveformView()
                    .matchedGeometryEffect(id: GeometryIDs.waveform, in: namespace)
            }
        }
        .animation(.easeInOut(duration: MotionConstants.colorBleedDuration), value: snapshot?.persistentID)
        .animation(.easeInOut(duration: MotionConstants.colorBleedDuration), value: snapshot?.accent)
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

    @ViewBuilder
    private func art(_ snapshot: NowPlayingSnapshot?) -> some View {
        let side: CGFloat = session.island.visualState == .expanded ? 92 : 22
        let colors = snapshot?.fallbackGradient ?? ArtworkFallback.gradient(artist: "", album: "idle")
        ZStack {
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [
                    (snapshot?.accent ?? colors[0]).opacity(0.45),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 2,
                endRadius: side
            )
            .blendMode(.plusLighter)
            if let image = snapshot?.artwork {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
                    .id(snapshot?.persistentID)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.28, style: .continuous))
        .shadow(color: (snapshot?.accent ?? colors[0]).opacity(0.55), radius: session.island.visualState == .expanded ? 14 : 5)
        .animation(.easeInOut(duration: MotionConstants.colorBleedDuration), value: snapshot?.persistentID)
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

    private func syncPolling() {
        if session.island.visualState == .expanded, session.music.snapshot?.isPlaying == true {
            session.music.startPositionPolling()
        } else {
            session.music.stopPositionPolling()
        }
    }
}
