import AVFoundation
import Foundation

@MainActor
final class WaveformAnalyzer: ObservableObject {
    unowned let session: AppSession
    @Published var peaks: [Float] = []
    @Published var persistentID: String?

    init(session: AppSession) {
        self.session = session
    }

    func start() {}

    func analyze(fileURL: URL?, persistentID: String) {
        guard let fileURL else {
            peaks = []
            self.persistentID = persistentID
            return
        }
        if let cached = loadCache(id: persistentID) {
            peaks = cached
            self.persistentID = persistentID
            return
        }
        Task.detached(priority: .utility) { [weak self] in
            let decoded = Self.decodePeaks(url: fileURL, count: 400)
            await MainActor.run {
                self?.peaks = decoded
                self?.persistentID = persistentID
                self?.saveCache(id: persistentID, peaks: decoded)
            }
        }
    }

    private func cacheURL(id: String) -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Halo/waveforms", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("\(id).peaks")
    }

    private func loadCache(id: String) -> [Float]? {
        let url = cacheURL(id: id)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
    }

    private func saveCache(id: String, peaks: [Float]) {
        let url = cacheURL(id: id)
        peaks.withUnsafeBufferPointer { buf in
            let data = Data(buffer: buf)
            try? data.write(to: url)
        }
    }

    nonisolated static func decodePeaks(url: URL, count: Int) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?[0]
        else { return [] }
        let total = Int(buffer.frameLength)
        let step = max(total / count, 1)
        var peaks = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let start = i * step
            let end = min(start + step, total)
            var peak: Float = 0
            if start < end {
                for f in start..<end {
                    peak = max(peak, abs(channel[f]))
                }
            }
            peaks[i] = peak
        }
        return peaks
    }
}
