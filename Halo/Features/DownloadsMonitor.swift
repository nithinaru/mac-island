import Foundation
import SwiftUI

@MainActor
final class DownloadsMonitor: ObservableObject {
    unowned let session: AppSession
    @Published var status: DownloadStatus?
    private var stream: FSEventStreamRef?

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        guard session.settings.downloads else { return }
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let paths = [dir.path as CFString] as CFArray
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else { return }
                Unmanaged<DownloadsMonitor>.fromOpaque(info).takeUnretainedValue().scan()
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
    }

    func scan() {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return }
        let partials = items.filter { ["download", "crdownload", "part"].contains($0.pathExtension.lowercased()) }
        guard let first = partials.first else { return }
        let status = DownloadStatus(url: first, filename: first.lastPathComponent, fraction: nil, count: partials.count)
        self.status = status
        session.island.post(.download(status))
    }
}

struct DownloadView: View {
    var status: DownloadStatus

    var body: some View {
        HStack {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.white)
            VStack(alignment: .leading) {
                Text(status.filename).lineLimit(1).foregroundStyle(.white)
                if let fraction = status.fraction {
                    ProgressView(value: fraction).tint(.white)
                } else {
                    Text("\(status.count) downloading").font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
}
