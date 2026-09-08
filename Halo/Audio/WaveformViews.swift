import SwiftUI

struct CompactWaveformView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: session.island.visualState == .idle)) { _ in
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(session.processTap.bars.enumerated()), id: \.offset) { _, value in
                    Capsule()
                        .fill(session.music.snapshot?.accent ?? .white)
                        .frame(width: 3, height: max(4, CGFloat(value) * 18))
                }
            }
        }
        .frame(width: 36, height: 22)
    }
}

struct WaveformSeekBar: View {
    @EnvironmentObject private var session: AppSession
    @State private var dragging = false
    @State private var dragProgress: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let peaks = session.waveform.peaks
            let duration = max(session.music.snapshot?.duration ?? 1, 0.001)
            let position = session.music.snapshot?.position ?? session.music.position
            let progress = dragging ? dragProgress : CGFloat(position / duration)
            WaveformShape(peaks: peaks)
                .fill(Color.white.opacity(0.22))
            WaveformShape(peaks: peaks)
                .fill(session.music.snapshot?.accent ?? Color.white)
                .mask(alignment: .leading) {
                    Rectangle().frame(width: proxy.size.width * progress)
                }
        }
        .frame(height: 28)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard session.island.visualState == .expanded else { return }
                    dragging = true
                    let width = max(value.startLocation.x + value.translation.width, 0)
                    dragProgress = min(max(width / 280, 0), 1)
                }
                .onEnded { _ in
                    let duration = session.music.snapshot?.duration ?? 0
                    session.music.seek(to: duration * Double(dragProgress))
                    dragging = false
                }
        )
    }
}

struct WaveformShape: Shape {
    var peaks: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let count = max(peaks.count, 2)
        let step = rect.width / CGFloat(count - 1)
        let mid = rect.midY
        path.move(to: CGPoint(x: 0, y: mid))
        for (i, peak) in peaks.enumerated() {
            let x = CGFloat(i) * step
            let amp = CGFloat(peak) * rect.height * 0.48
            path.addLine(to: CGPoint(x: x, y: mid - amp))
        }
        for (i, peak) in peaks.enumerated().reversed() {
            let x = CGFloat(i) * step
            let amp = CGFloat(peak) * rect.height * 0.48
            path.addLine(to: CGPoint(x: x, y: mid + amp))
        }
        path.closeSubpath()
        return path
    }
}

struct EdgeScrubber: ViewModifier {
    @EnvironmentObject private var session: AppSession

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    guard session.settings.edgeScrubbing,
                          session.island.visualState == .expanded,
                          let snap = session.music.snapshot
                    else { return }
                    let progress = min(max(value.location.x / max(session.geometry.metrics.expandedSize.width, 1), 0), 1)
                    session.music.seek(to: snap.duration * Double(progress))
                }
        )
    }
}
