import Combine
import Foundation
import SwiftUI

@MainActor
final class FocusTimer: ObservableObject {
    unowned let session: AppSession
    @Published var progress: Double = 0
    @Published var isRunning = false
    private var startedAt: Date?
    var duration: TimeInterval = 25 * 60

    init(session: AppSession) {
        self.session = session
    }

    func toggle() {
        if isRunning {
            isRunning = false
            startedAt = nil
            session.island.clearTransient()
        } else {
            isRunning = true
            startedAt = Date()
            tick()
        }
    }

    func tick() {
        guard isRunning, let startedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        progress = min(elapsed / duration, 1)
        session.island.post(.focus(progress: progress), duration: nil)
        if progress >= 1 {
            isRunning = false
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.tick()
            }
        }
    }
}

struct FocusArcView: View {
    var progress: Double

    var body: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: 22, height: 22)
    }
}
