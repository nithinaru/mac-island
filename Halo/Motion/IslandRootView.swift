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
                .padding(.horizontal, state == .expanded ? 18 : 8)
                .padding(.top, state == .expanded ? metrics.notchHeight + 8 : 0)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(islandClipShape(size: size, metrics: metrics, state: state))
        .contentShape(islandClipShape(size: size, metrics: metrics, state: state))
        .shadow(color: .black.opacity(idleOnHardware ? 0 : 0.35), radius: 18, y: 8)
        .opacity(idleOnHardware ? 0.02 : 1)
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

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 18, height: 18)
                .matchedGeometryEffect(id: GeometryIDs.art, in: namespace)
            if state != .idle {
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(height: 8)
                    .matchedGeometryEffect(id: GeometryIDs.title, in: namespace)
            }
            if state == .expanded {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(Color.white.opacity(0.5)).frame(width: 120, height: 8)
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 80, height: 8)
                        .matchedGeometryEffect(id: GeometryIDs.waveform, in: namespace)
                }
            } else if state == .compact {
                Capsule()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 36, height: 10)
                    .matchedGeometryEffect(id: GeometryIDs.waveform, in: namespace)
            }
        }
        .padding(.horizontal, 10)
    }
}

struct TransientHostView: View {
    var event: TransientEvent
    var state: IslandState
    var namespace: Namespace.ID
    @EnvironmentObject private var session: AppSession

    var body: some View {
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
}
