import Combine
import Foundation
import SwiftUI

@MainActor
final class FocusTimer: ObservableObject {
    unowned let session: AppSession
    @Published var progress: Double = 0
    @Published var isRunning = false
    private var startedAt: Date?
    private var tickTimer: Timer?
    var duration: TimeInterval = 25 * 60

    init(session: AppSession) {
        self.session = session
    }

    func toggle() {
        if isRunning {
            stop()
        } else {
            guard session.settings.focus else { return }
            isRunning = true
            startedAt = Date()
            progress = 0
            session.island.post(.focus(progress: 0), duration: nil)
            tickTimer?.invalidate()
            tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.tick()
                }
            }
            tick()
        }
    }

    func tick() {
        guard isRunning, let startedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        progress = min(elapsed / duration, 1)
        if progress >= 1 {
            stop()
        }
    }

    private func stop() {
        isRunning = false
        startedAt = nil
        tickTimer?.invalidate()
        tickTimer = nil
        if case .focus = session.island.transient {
            session.island.clearTransient()
        }
        progress = 0
    }
}

struct FocusArcView: View {
    var progress: Double
    @EnvironmentObject private var session: AppSession

    var body: some View {
        let remaining = max(0, min(1, 1 - session.focus.progress))
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: proxy.size.height / 2, style: .continuous)
                .trim(from: 0, to: remaining)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .padding(-8)
                .rotationEffect(.degrees(-90))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
