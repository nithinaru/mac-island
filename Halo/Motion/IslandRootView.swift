import SwiftUI

struct IslandRootView: View {
    @EnvironmentObject private var session: AppSession
    @Namespace private var islandNS

    var body: some View {
        GeometryReader { proxy in
            let metrics = session.geometry.metrics
            let size = currentSize(metrics)
            VStack(spacing: 0) {
                island(size: size, metrics: metrics)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .matchedGeometryEffect(id: GeometryIDs.pill, in: islandNS, properties: .frame)
                Spacer(minLength: 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background(Color.clear)
        .onAppear {
            session.settings.syncMotionConstants()
        }
    }

    @ViewBuilder
    private func island(size: CGSize, metrics: NotchMetrics) -> some View {
        let state = session.island.visualState
        let idleOnHardware = state == .idle && !metrics.isFallbackPill
        ZStack(alignment: .top) {
            IslandChrome(
                size: size,
                metrics: metrics,
                state: state,
                glow: session.music.snapshot?.accent ?? Color.white.opacity(0.2),
                glowPulse: session.tempo.pulse,
                gooDetached: session.island.gooDetached
            )
            IslandContentView(namespace: islandNS)
                .padding(.horizontal, state == .expanded ? 14 : 0)
                .padding(.top, state == .expanded ? metrics.notchHeight + 8 : 0)
                .padding(.bottom, state == .expanded ? 10 : 0)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(islandClipShape(size: size, metrics: metrics, state: state))
        .contentShape(islandClipShape(size: size, metrics: metrics, state: state))
        .shadow(color: .black.opacity(idleOnHardware ? 0 : 0.35), radius: 18, y: 8)
        .opacity(1)
        .modifier(EdgeScrubber())
        .onHover { hovering in
            session.island.setHover(hovering)
        }
        .contextMenu {
            IslandContextMenu()
                .environmentObject(session)
        }
    }

    private func currentSize(_ metrics: NotchMetrics) -> CGSize {
        switch session.island.visualState {
        case .idle:
            return metrics.idleSize
        case .compact:
            return metrics.compactSize
        case .expanded:
            return metrics.expandedSize
        }
    }
}

struct IslandContentView: View {
    var namespace: Namespace.ID
    @EnvironmentObject private var session: AppSession

    var body: some View {
        let state = session.island.visualState
        if let transient = session.island.transient {
            TransientHostView(event: transient, state: state, namespace: namespace)
        } else if session.music.snapshot != nil {
            NowPlayingView(namespace: namespace)
        } else if state == .idle {
            Color.clear
        } else {
            PlaceholderIslandView(state: state, namespace: namespace)
        }
    }
}

struct PlaceholderIslandView: View {
    var state: IslandState
    var namespace: Namespace.ID
    @EnvironmentObject private var session: AppSession

    var body: some View {
        let notchWidth = session.geometry.metrics.idleSize.width
        if state == .expanded {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .matchedGeometryEffect(id: GeometryIDs.art, in: namespace)
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(Color.white.opacity(0.5)).frame(width: 120, height: 8)
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 80, height: 8)
                        .matchedGeometryEffect(id: GeometryIDs.waveform, in: namespace)
                }
                Spacer(minLength: 0)
            }
        } else {
            CompactWingLayout(notchWidth: notchWidth) {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 16, height: 16)
                    .matchedGeometryEffect(id: GeometryIDs.art, in: namespace)
            } right: {
                Capsule()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 28, height: 8)
                    .matchedGeometryEffect(id: GeometryIDs.waveform, in: namespace)
            }
        }
    }
}

struct TransientHostView: View {
    var event: TransientEvent
    var state: IslandState
    var namespace: Namespace.ID
    @EnvironmentObject private var session: AppSession

    var body: some View {
        let notchWidth = session.geometry.metrics.idleSize.width
        if state == .expanded {
            expandedBody
        } else {
            CompactWingLayout(notchWidth: notchWidth) {
                leftWing
            } right: {
                rightWing
            }
        }
    }

    @ViewBuilder
    private var leftWing: some View {
        switch event {
        case .volume(_, let muted):
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .foregroundStyle(.white)
                .font(.system(size: 11, weight: .semibold))
        case .brightness:
            Image(systemName: "sun.max.fill")
                .foregroundStyle(.white)
                .font(.system(size: 11, weight: .semibold))
        case .charging:
            Image(systemName: "bolt.fill")
                .foregroundStyle(.green)
                .font(.system(size: 11, weight: .semibold))
        case .liveActivity(let payload):
            Image(systemName: payload.symbol ?? "sparkles")
                .foregroundStyle(.white)
                .font(.system(size: 11, weight: .semibold))
        case .screenshot:
            Image(systemName: "camera.fill")
                .foregroundStyle(.white)
                .font(.system(size: 11, weight: .semibold))
        case .download:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.white)
                .font(.system(size: 11, weight: .semibold))
        case .privacy:
            Image(systemName: "mic.fill")
                .foregroundStyle(.green)
                .font(.system(size: 11, weight: .semibold))
        case .exclusivity:
            Image(systemName: "speaker.slash.fill")
                .foregroundStyle(.white)
                .font(.system(size: 11, weight: .semibold))
        case .focus:
            Image(systemName: "timer")
                .foregroundStyle(.orange)
                .font(.system(size: 11, weight: .semibold))
        case .sleepTimer:
            Image(systemName: "moon.zzz.fill")
                .foregroundStyle(.white)
                .font(.system(size: 11, weight: .semibold))
        case .meeting:
            Image(systemName: "calendar")
                .foregroundStyle(.white)
                .font(.system(size: 11, weight: .semibold))
        case .clipboard:
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.white)
                .font(.system(size: 11, weight: .semibold))
        case .devices:
            Image(systemName: "hifispeaker.fill")
                .foregroundStyle(.white)
                .font(.system(size: 11, weight: .semibold))
        case .mixer:
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.white)
                .font(.system(size: 11, weight: .semibold))
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        switch event {
        case .volume(let level, _):
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 34, height: 4)
                .overlay(alignment: .leading) {
                    Capsule().fill(Color.white).frame(width: 34 * CGFloat(level))
                }
        case .brightness(let value):
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 34, height: 4)
                .overlay(alignment: .leading) {
                    Capsule().fill(Color.white).frame(width: 34 * CGFloat(value))
                }
        case .charging(let percent, _):
            Text("\(percent)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        case .liveActivity(let payload):
            Text(payload.title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
        case .screenshot:
            Text("Shot")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        case .download(let status):
            Text(status.filename)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
        case .privacy(let status):
            Text(status.micApps.first?.name ?? "Mic")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
        case .exclusivity(let alert):
            Text(alert.name)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
        case .focus(let progress):
            FocusArcView(progress: progress)
        case .sleepTimer(let remaining, _):
            Text(timeString(remaining))
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        case .meeting(let payload):
            Text(payload.title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
        case .clipboard:
            Text("Copied")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        case .devices:
            Text("Output")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        case .mixer:
            Text("Audio")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var expandedBody: some View {
        switch event {
        case .volume(let level, let muted):
            HUDMeterView(symbol: muted ? "speaker.slash.fill" : "speaker.wave.3.fill", value: CGFloat(level))
        case .brightness(let value):
            HUDMeterView(symbol: "sun.max.fill", value: CGFloat(value))
        case .charging(let percent, let isCharging):
            ChargingView(percent: percent, isCharging: isCharging)
        case .screenshot(let url):
            ScreenshotCard(url: url)
        case .liveActivity(let payload):
            LiveActivityView(payload: payload)
        case .download(let status):
            DownloadView(status: status)
        case .meeting(let payload):
            MeetingJoinView(payload: payload)
        case .clipboard:
            ClipboardRingView()
        case .focus(let progress):
            FocusArcView(progress: progress)
        case .privacy(let status):
            PrivacyView(status: status)
        case .exclusivity(let alert):
            ExclusivityAlertView(alert: alert)
        case .devices:
            OutputDeviceView()
        case .mixer:
            AppMixerView()
        case .sleepTimer(let remaining, let total):
            SleepTimerView(remaining: remaining, total: total)
        }
    }

    private func timeString(_ remaining: TimeInterval) -> String {
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
