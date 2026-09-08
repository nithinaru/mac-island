import AudioToolbox
import Combine
import CoreAudio
import Foundation

@MainActor
final class MusicProcessTap: ObservableObject {
    unowned let session: AppSession
    @Published var level: Float = 0
    @Published var bars: [Float] = Array(repeating: 0.12, count: 7)

    private var envelope: Float = 0

    init(session: AppSession) {
        self.session = session
    }

    func start() {}

    func tick(outputLevel: Float) {
        let attack: Float = 0.03
        let release: Float = 0.2
        let dt: Float = 1.0 / 120.0
        if outputLevel > envelope {
            envelope += (outputLevel - envelope) * min(1, dt / attack)
        } else {
            envelope += (outputLevel - envelope) * min(1, dt / release)
        }
        level = envelope
        bars = (0..<7).map { i in
            let wobble = Float(i + 1) / 8
            return max(0.08, min(1, envelope * (0.55 + wobble)))
        }
    }
}
