import Accelerate
import AVFoundation
import Foundation

@MainActor
final class WaveformAnalyzer: ObservableObject {
    unowned let session: AppSession
    @Published var peaks: [Float] = []
    @Published var persistentID: String?

    private var generation: UInt64 = 0

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        Self.ensureCacheDirectory()
    }

    func analyze(fileURL: URL?, persistentID: String) {
        generation += 1
        let token = generation

        if self.persistentID == persistentID, !peaks.isEmpty {
            return
        }

        if let cached = Self.loadCache(id: persistentID) {
            peaks = cached
            self.persistentID = persistentID
            return
        }

        guard let fileURL else {
            peaks = []
            self.persistentID = persistentID
            return
        }

        Task { [weak self] in
            let decoded = await Task.detached(priority: .utility) {
                Self.decodePeaks(url: fileURL, count: 400)
            }.value
            guard let self, self.generation == token else { return }
            self.peaks = decoded
            self.persistentID = persistentID
            if !decoded.isEmpty {
                Self.saveCache(id: persistentID, peaks: decoded)
            }
        }
    }

    static func cacheRoot() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Halo/waveforms", isDirectory: true)
    }

    private static func ensureCacheDirectory() {
        try? FileManager.default.createDirectory(at: cacheRoot(), withIntermediateDirectories: true)
    }

    private static func cacheURL(id: String) -> URL {
        cacheRoot().appendingPathComponent("\(id).peaks")
    }

    private static func loadCache(id: String) -> [Float]? {
        let url = cacheURL(id: id)
        guard let data = try? Data(contentsOf: url), data.count >= MemoryLayout<Float>.size else { return nil }
        let count = data.count / MemoryLayout<Float>.size
        guard count == 400, data.count == count * MemoryLayout<Float>.size else { return nil }
        return data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
    }

    private static func saveCache(id: String, peaks: [Float]) {
        ensureCacheDirectory()
        let url = cacheURL(id: id)
        peaks.withUnsafeBufferPointer { buf in
            let data = Data(buffer: buf)
            try? data.write(to: url, options: .atomic)
        }
    }

    nonisolated static func decodePeaks(url: URL, count: Int) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let format = file.processingFormat
        let total = Int(file.length)
        guard total > 0, count > 0, format.channelCount > 0 else { return [] }

        let framesPerBin = max(total / count, 1)
        var peaks = [Float](repeating: 0, count: count)
        let chunkFrames = min(max(framesPerBin, 2048), 16_384)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunkFrames)) else {
            return []
        }

        let channels = Int(format.channelCount)
        var frameIndex = 0
        while frameIndex < total {
            let toRead = min(chunkFrames, total - frameIndex)
            file.framePosition = AVAudioFramePosition(frameIndex)
            do {
                try file.read(into: buffer, frameCount: AVAudioFrameCount(toRead))
            } catch {
                return []
            }
            let n = Int(buffer.frameLength)
            guard n > 0, let channelData = buffer.floatChannelData else { break }

            for i in 0..<n {
                var absSample: Float = 0
                for channel in 0..<channels {
                    absSample = max(absSample, abs(channelData[channel][i]))
                }
                let bin = min((frameIndex + i) / framesPerBin, count - 1)
                if absSample > peaks[bin] {
                    peaks[bin] = absSample
                }
            }
            frameIndex += n
            if n < toRead { break }
        }

        var maxPeak: Float = 0
        vDSP_maxv(peaks, 1, &maxPeak, vDSP_Length(count))
        guard maxPeak > 0 else { return [] }
        var scale = 1 / maxPeak
        vDSP_vsmul(peaks, 1, &scale, &peaks, 1, vDSP_Length(count))
        return peaks
    }
}
