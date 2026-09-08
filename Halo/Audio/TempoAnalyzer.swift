import Accelerate
import AVFoundation
import Combine
import Foundation
import QuartzCore

@MainActor
final class TempoAnalyzer: ObservableObject {
    unowned let session: AppSession
    @Published var bpm: Double = 0
    @Published var pulse: CGFloat = 1

    private var generation: UInt64 = 0
    private var cancellables: Set<AnyCancellable> = []
    init(session: AppSession) {
        self.session = session
    }

    func start() {
        Self.ensureCacheDirectory()
        session.music.$snapshot
            .combineLatest(session.island.$visualState)
            .sink { [weak self] snapshot, state in
                self?.syncIdlePulse(playing: snapshot?.isPlaying == true, state: state)
            }
            .store(in: &cancellables)
    }

    func update(taggedBPM: Int, fileURL: URL?, persistentID: String) {
        generation += 1
        let token = generation

        if taggedBPM > 0 {
            bpm = Double(taggedBPM)
            return
        }

        if let cached = Self.loadCache(id: persistentID), cached > 0 {
            bpm = cached
            return
        }

        bpm = 0
        guard let fileURL else { return }

        Task { [weak self] in
            let estimated = await Task.detached(priority: .utility) {
                Self.estimateBPM(url: fileURL)
            }.value
            guard let self, self.generation == token else { return }
            self.bpm = estimated
            if estimated > 0 {
                Self.saveCache(id: persistentID, bpm: estimated)
            }
        }
    }

    /// Display-synced beat pulse. Driven by `TempoPulseDriver` (`TimelineView`), not `Timer`.
    func tick(at date: Date) {
        guard session.settings.bpmBreathing,
              bpm > 0,
              session.music.snapshot?.isPlaying == true,
              session.island.visualState != .idle
        else {
            idlePulse()
            return
        }
        let period = 60.0 / bpm
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        let wave = 0.5 + 0.5 * sin(phase * 2 * .pi)
        pulse = 0.72 + 0.28 * wave
    }

    func idlePulse() {
        if pulse != 1 {
            pulse = 1
        }
    }

    private func syncIdlePulse(playing: Bool, state: IslandState) {
        if !session.settings.bpmBreathing || !playing || state == .idle || bpm <= 0 {
            idlePulse()
        }
    }

    static func cacheRoot() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Halo/tempos", isDirectory: true)
    }

    private static func ensureCacheDirectory() {
        try? FileManager.default.createDirectory(at: cacheRoot(), withIntermediateDirectories: true)
    }

    private static func cacheURL(id: String) -> URL {
        cacheRoot().appendingPathComponent("\(id).bpm")
    }

    private static func loadCache(id: String) -> Double? {
        let url = cacheURL(id: id)
        guard let data = try? Data(contentsOf: url), data.count == MemoryLayout<Double>.size else { return nil }
        return data.withUnsafeBytes { $0.load(as: Double.self) }
    }

    private static func saveCache(id: String, bpm: Double) {
        ensureCacheDirectory()
        var value = bpm
        let data = Data(bytes: &value, count: MemoryLayout<Double>.size)
        try? data.write(to: cacheURL(id: id), options: .atomic)
    }

    /// Onset (first-difference energy) + vDSP autocorrelation on the first 30 seconds.
    nonisolated static func estimateBPM(url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0, format.channelCount > 0 else { return 0 }

        let maxFrames = Int(min(file.length, AVAudioFramePosition(sampleRate * 30)))
        guard maxFrames > Int(sampleRate) else { return 0 }

        var mono = [Float](repeating: 0, count: maxFrames)
        let chunk = 8192
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk)) else {
            return 0
        }
        let channels = Int(format.channelCount)
        var written = 0
        file.framePosition = 0
        while written < maxFrames {
            let toRead = min(chunk, maxFrames - written)
            do {
                try file.read(into: buffer, frameCount: AVAudioFrameCount(toRead))
            } catch {
                return 0
            }
            let n = Int(buffer.frameLength)
            guard n > 0, let data = buffer.floatChannelData else { break }
            let scale = 1 / Float(channels)
            for i in 0..<n {
                var sum: Float = 0
                for channel in 0..<channels {
                    sum += data[channel][i]
                }
                mono[written + i] = sum * scale
            }
            written += n
            if n < toRead { break }
        }
        guard written > Int(sampleRate / 2) else { return 0 }

        var onset = [Float](repeating: 0, count: written)
        onset[0] = abs(mono[0])
        for i in 1..<written {
            let delta = mono[i] - mono[i - 1]
            onset[i] = delta > 0 ? delta : 0
        }

        let hop = 512
        let envCount = written / hop
        guard envCount > 64 else { return 0 }
        var env = [Float](repeating: 0, count: envCount)
        onset.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            for i in 0..<envCount {
                var sum: Float = 0
                vDSP_sve(base + i * hop, 1, &sum, vDSP_Length(hop))
                env[i] = sum
            }
        }

        var mean: Float = 0
        vDSP_meanv(env, 1, &mean, vDSP_Length(envCount))
        var negMean = -mean
        vDSP_vsadd(env, 1, &negMean, &env, 1, vDSP_Length(envCount))

        let envRate = sampleRate / Double(hop)
        let minLag = max(Int(envRate * 60.0 / 180.0), 2)
        let maxLag = min(Int(envRate * 60.0 / 60.0), envCount / 2)
        guard maxLag > minLag else { return 0 }

        var bestLag = 0
        var bestCorr: Float = 0
        env.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            for lag in minLag...maxLag {
                var corr: Float = 0
                vDSP_dotpr(base, 1, base + lag, 1, &corr, vDSP_Length(envCount - lag))
                if corr > bestCorr {
                    bestCorr = corr
                    bestLag = lag
                }
            }
        }
        guard bestLag > 0, bestCorr > 0 else { return 0 }

        let seconds = Double(bestLag) / envRate
        let raw = 60.0 / seconds
        let folded: Double
        if raw > 180 {
            folded = raw / 2
        } else if raw < 60 {
            folded = raw * 2
        } else {
            folded = raw
        }
        return min(max(folded, 60), 180)
    }
}
