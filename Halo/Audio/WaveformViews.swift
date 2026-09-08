import SwiftUI

/// Display-synced BPM pulse. `TimelineView` is paused when idle / not playing so idle CPU stays near zero.
struct TempoPulseDriver: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        let active = session.settings.bpmBreathing
            && session.tempo.bpm > 0
            && session.music.snapshot?.isPlaying == true
            && session.island.visualState != .idle
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !active)) { context in
            Color.clear
                .frame(width: 0, height: 0)
                .onChange(of: context.date) { _, date in
                    session.tempo.tick(at: date)
                }
        }
        .onChange(of: active) { _, isActive in
            if !isActive {
                session.tempo.idlePulse()
            }
        }
        .onDisappear {
            session.tempo.idlePulse()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct CompactWaveformView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        let playing = session.music.snapshot?.isPlaying == true
        let accent = session.music.snapshot?.accent ?? .white
        let values: [Float] = {
            if session.settings.reactiveWaveform, playing {
                return session.processTap.bars
            }
            return Array(repeating: 0.10, count: session.processTap.bars.count)
        }()

        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Capsule()
                    .fill(accent)
                    .frame(width: 3, height: max(4, CGFloat(value) * 18))
            }
        }
        .frame(width: 36, height: 22)
        .overlay { TempoPulseDriver() }
        .allowsHitTesting(false)
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
            let progress = dragging ? dragProgress : CGFloat(min(max(position / duration, 0), 1))
            let accent = session.music.snapshot?.accent ?? Color.white
            let width = proxy.size.width

            ZStack(alignment: .leading) {
                if peaks.isEmpty {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(accent)
                        .frame(width: max(0, width * progress))
                } else {
                    WaveformShape(peaks: peaks)
                        .fill(Color.white.opacity(0.22))
                    WaveformShape(peaks: peaks)
                        .fill(accent)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: width * progress)
                        }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard session.island.visualState == .expanded else { return }
                        dragging = true
                        let x = min(max(value.location.x, 0), width)
                        dragProgress = width > 0 ? x / width : 0
                        session.music.seek(to: duration * Double(dragProgress))
                    }
                    .onEnded { value in
                        guard session.island.visualState == .expanded else {
                            dragging = false
                            return
                        }
                        let x = min(max(value.location.x, 0), width)
                        dragProgress = width > 0 ? x / width : 0
                        session.music.seek(to: duration * Double(dragProgress))
                        dragging = false
                    }
            )
        }
        .frame(height: 28)
        .overlay { TempoPulseDriver() }
    }
}

struct WaveformShape: Shape {
    var peaks: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !peaks.isEmpty, rect.width > 0, rect.height > 0 else { return path }
        let count = peaks.count
        let step = rect.width / CGFloat(max(count, 1))
        let mid = rect.midY
        let barWidth = max(step * 0.72, 0.6)

        for (i, peak) in peaks.enumerated() {
            let x = CGFloat(i) * step + (step - barWidth) * 0.5
            let amp = CGFloat(max(peak, 0.02)) * rect.height * 0.48
            let column = CGRect(x: x, y: mid - amp, width: barWidth, height: amp * 2)
            path.addRoundedRect(in: column, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
        }
        return path
    }
}

struct EdgeScrubber: ViewModifier {
    @EnvironmentObject private var session: AppSession

    func body(content: Content) -> some View {
        let expanded = session.island.visualState == .expanded
        let enabled = session.settings.edgeScrubbing && expanded
        content
            .overlay(alignment: .bottom) {
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { value in
                                    guard session.settings.edgeScrubbing,
                                          session.island.visualState == .expanded,
                                          let snap = session.music.snapshot
                                    else { return }
                                    let width = max(proxy.size.width, 1)
                                    let progress = min(max(value.location.x / width, 0), 1)
                                    session.music.seek(to: snap.duration * Double(progress))
                                }
                        )
                }
                .frame(height: 16)
                .allowsHitTesting(enabled)
            }
    }
}
