import Accelerate
import AppKit
import AVFoundation
import Combine
import Foundation
import QuartzCore

@MainActor
final class TempoAnalyzer: ObservableObject {
    unowned let session: AppSession
    @Published var bpm: Double = 0
    @Published var pulse: CGFloat = 1

    private var displayLink: CADisplayLink?
    private var beatPhase: Double = 0

    init(session: AppSession) {
        self.session = session
    }

    func start() {}

    func update(taggedBPM: Int, fileURL: URL?, persistentID: String) {
        if taggedBPM > 0 {
            bpm = Double(taggedBPM)
        } else if let fileURL {
            Task.detached(priority: .utility) { [weak self] in
                let estimated = Self.estimateBPM(url: fileURL)
                await MainActor.run {
                    self?.bpm = estimated
                }
            }
        }
        startPulse()
    }

    func startPulse() {
        displayLink?.invalidate()
        let link = NSScreen.main?.displayLink(target: self, selector: #selector(tick(_:)))
        displayLink = link
        link?.add(to: .main, forMode: .common)
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard session.settings.bpmBreathing, bpm > 0, session.music.snapshot?.isPlaying == true else {
            pulse = 1
            return
        }
        beatPhase += link.duration * (bpm / 60.0)
        let wave = 0.5 + 0.5 * sin(beatPhase * 2 * .pi)
        pulse = 0.72 + 0.28 * wave
    }

    nonisolated static func estimateBPM(url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let sampleRate = file.processingFormat.sampleRate
        let frames = min(file.length, AVAudioFramePosition(sampleRate * 30))
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames)),
              (try? file.read(into: buffer, frameCount: AVAudioFrameCount(frames))) != nil,
              let samples = buffer.floatChannelData?[0]
        else { return 0 }

        let n = Int(buffer.frameLength)
        var windowed = [Float](repeating: 0, count: n)
        for i in 1..<n {
            windowed[i] = abs(samples[i] - samples[i - 1])
        }
        let hop = 512
        let envCount = n / hop
        guard envCount > 32 else { return 0 }
        var env = [Float](repeating: 0, count: envCount)
        for i in 0..<envCount {
            var sum: Float = 0
            let start = i * hop
            for j in 0..<hop { sum += windowed[start + j] }
            env[i] = sum
        }
        var mean: Float = 0
        vDSP_meanv(env, 1, &mean, vDSP_Length(envCount))
        var bestLag = 0
        var bestCorr: Float = 0
        let minLag = max(Int((60.0 / 180.0) * sampleRate / Double(hop)), 4)
        let maxLag = min(Int((60.0 / 60.0) * sampleRate / Double(hop)), envCount - 2)
        guard maxLag > minLag else { return 0 }
        for lag in minLag...maxLag {
            var corr: Float = 0
            let len = envCount - lag
            vDSP_dotpr(env, 1, env.dropFirst(lag).map { $0 }, 1, &corr, vDSP_Length(len))
            if corr > bestCorr {
                bestCorr = corr
                bestLag = lag
            }
        }
        guard bestLag > 0 else { return 0 }
        let seconds = Double(bestLag * hop) / sampleRate
        let bpm = 60.0 / seconds
        return min(max(bpm, 60), 180)
    }
}
