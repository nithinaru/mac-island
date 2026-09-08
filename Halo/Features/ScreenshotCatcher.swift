import AppKit
import Combine
import SwiftUI

@MainActor
final class ScreenshotCatcher: NSObject, ObservableObject, NSDraggingSource {
    unowned let session: AppSession
    @Published var latest: URL?
    private var stream: FSEventStreamRef?

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        guard session.settings.screenshots else { return }
        watch(directory: screenshotDirectory())
    }

    func screenshotDirectory() -> URL {
        let proc = Process()
        proc.launchPath = "/usr/bin/defaults"
        proc.arguments = ["read", "com.apple.screencapture", "location"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty, proc.terminationStatus == 0 {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    func watch(directory: URL) {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = [directory.path as CFString] as CFArray
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else { return }
                Unmanaged<ScreenshotCatcher>.fromOpaque(info).takeUnretainedValue().scan()
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.4,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return }
        self.stream = stream
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        FSEventStreamStart(stream)
    }

    func scan() {
        let dir = screenshotDirectory()
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let shot = items
            .filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }
        guard let shot, shot != latest, Date().timeIntervalSince((try? shot.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < 5 else { return }
        latest = shot
        session.island.post(.screenshot(shot))
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

struct ScreenshotCard: View {
    var url: URL

    var body: some View {
        HStack(spacing: 8) {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
            }
            Text("Screenshot")
                .foregroundStyle(.white)
                .font(.system(size: 11, weight: .semibold))
        }
    }
}
