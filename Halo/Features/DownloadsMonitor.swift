import Foundation
import SwiftUI

@MainActor
final class DownloadsMonitor: ObservableObject {
    unowned let session: AppSession
    @Published var status: DownloadStatus?
    private var stream: FSEventStreamRef?
    private var lastPostedSignature: String?
    private var showing = false

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        guard session.settings.downloads else { return }
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = [dir.path as CFString] as CFArray
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let monitor = Unmanaged<DownloadsMonitor>.fromOpaque(info).takeUnretainedValue()
                DispatchQueue.main.async {
                    monitor.scan()
                }
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )
        if let stream {
            FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            FSEventStreamStart(stream)
        }
        scan()
    }

    func scan() {
        guard session.settings.downloads else { return }
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let partials = items.filter { url in
            ["download", "crdownload", "part"].contains(url.pathExtension.lowercased())
        }

        guard !partials.isEmpty else {
            status = nil
            if showing {
                if case .download = session.island.transient {
                    session.island.clearTransient()
                }
                showing = false
                lastPostedSignature = nil
            }
            return
        }

        let ranked = partials.sorted { lhs, rhs in
            let left = SafariDownloadPlist.fraction(at: lhs) != nil
            let right = SafariDownloadPlist.fraction(at: rhs) != nil
            if left != right { return left && !right }
            return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }
        guard let first = ranked.first else { return }
        let fraction = SafariDownloadPlist.fraction(at: first)
        let next = DownloadStatus(
            url: first,
            filename: Self.displayName(for: first),
            fraction: fraction,
            count: partials.count
        )
        let nextPaths = Set(partials.map(\.path))
        let signature = nextPaths.sorted().joined(separator: "|")
        let previousPaths = Set((lastPostedSignature ?? "").split(separator: "|").map(String.init).filter { !$0.isEmpty })
        let appeared = nextPaths.subtracting(previousPaths)
        status = next

        if !showing || !appeared.isEmpty {
            lastPostedSignature = signature
            session.island.post(.download(next), duration: nil)
            showing = true
        } else {
            lastPostedSignature = signature
        }
    }

    private static func displayName(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "download" || ext == "crdownload" || ext == "part" {
            return url.deletingPathExtension().lastPathComponent
        }
        return url.lastPathComponent
    }
}

/// Safari `.download` bundles expose expected bytes in Info.plist.
/// Only a real total produces a percentage; otherwise the UI stays indeterminate.
enum SafariDownloadPlist {
    static func fraction(at url: URL) -> Double? {
        guard url.pathExtension.lowercased() == "download" else { return nil }
        let plistURL = url.appendingPathComponent("Info.plist")
        guard let dict = NSDictionary(contentsOf: plistURL) as? [String: Any] else { return nil }
        guard let total = number(dict, keys: [
            "DownloadEntryProgressTotalToLoad",
            "NSURLDownloadExpectedContentLength"
        ]), total > 0 else { return nil }
        guard let soFar = number(dict, keys: [
            "DownloadEntryProgressBytesSoFar",
            "NSURLDownloadBytesReceived"
        ]), soFar >= 0 else { return nil }
        return min(1, max(0, soFar / total))
    }

    private static func number(_ dict: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = dict[key] as? NSNumber {
                return value.doubleValue
            }
            if let value = dict[key] as? Double {
                return value
            }
            if let value = dict[key] as? Int {
                return Double(value)
            }
        }
        return nil
    }
}

struct DownloadView: View {
    var status: DownloadStatus
    @EnvironmentObject private var session: AppSession

    private var live: DownloadStatus {
        session.downloads.status ?? status
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 4) {
                Text(live.filename)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .font(.system(size: 11, weight: .semibold))
                if let fraction = live.fraction {
                    ProgressView(value: fraction)
                        .tint(.white)
                        .frame(width: 88)
                } else {
                    DownloadShimmerBar()
                    Text("\(live.count) downloading")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
}

struct DownloadShimmerBar: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let travel = (sin(t * 2.6) + 1) / 2
            Capsule()
                .fill(Color.white.opacity(0.12))
                .frame(width: 88, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 28, height: 4)
                        .offset(x: 60 * travel)
                }
                .clipped()
        }
    }
}
