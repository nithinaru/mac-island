import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ScreenshotCatcher: NSObject, ObservableObject, NSDraggingSource {
    unowned let session: AppSession
    @Published var latest: URL?
    private var stream: FSEventStreamRef?
    private var seen = Set<URL>()

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        guard session.settings.screenshots else { return }
        seen = existingImages(in: screenshotDirectory())
        watch(directory: screenshotDirectory())
    }

    func screenshotDirectory() -> URL {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        proc.arguments = ["read", "com.apple.screencapture", "location"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty, proc.terminationStatus == 0 {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    func watch(directory: URL) {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
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
                let catcher = Unmanaged<ScreenshotCatcher>.fromOpaque(info).takeUnretainedValue()
                Task { @MainActor in
                    catcher.scan()
                }
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
        guard session.settings.screenshots else { return }
        let dir = screenshotDirectory()
        let images = existingImages(in: dir)
        let shot = images
            .filter { !seen.contains($0) }
            .max { a, b in
                modificationDate(a) < modificationDate(b)
            }
        guard let shot else { return }
        seen = images
        let modified = modificationDate(shot)
        guard Date().timeIntervalSince(modified) < 8 else { return }
        latest = shot
        session.island.post(.screenshot(shot))
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .outsideApplication:
            return .copy
        case .withinApplication:
            return .copy
        @unknown default:
            return .copy
        }
    }

    func itemProvider(for url: URL) -> NSItemProvider {
        let type = UTType(filenameExtension: url.pathExtension) ?? .png
        let provider = NSItemProvider()
        provider.registerFileRepresentation(
            forTypeIdentifier: type.identifier,
            fileOptions: .openInPlace,
            visibility: .all
        ) { completion in
            completion(url, true, nil)
            return nil
        }
        provider.registerObject(url as NSURL, visibility: .all)
        return provider
    }

    private func existingImages(in directory: URL) -> Set<URL> {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return Set(items.filter { Self.isScreenshotFile($0) })
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func isScreenshotFile(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "heic"].contains(url.pathExtension.lowercased())
    }
}

private final class ScreenshotDragView: NSView {
    var url: URL
    weak var source: ScreenshotCatcher?

    init(url: URL, source: ScreenshotCatcher) {
        self.url = url
        self.source = source
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDragged(with event: NSEvent) {
        guard let source else { return }
        let writer = url as NSURL
        let item = NSDraggingItem(pasteboardWriter: writer)
        let preview = NSImage(contentsOf: url)
        item.setDraggingFrame(bounds, contents: preview)
        beginDraggingSession(with: [item], event: event, source: source)
    }
}

private struct ScreenshotDragHandle: NSViewRepresentable {
    var url: URL
    var source: ScreenshotCatcher

    func makeNSView(context: Context) -> ScreenshotDragView {
        ScreenshotDragView(url: url, source: source)
    }

    func updateNSView(_ nsView: ScreenshotDragView, context: Context) {
        nsView.url = url
        nsView.source = source
    }
}

struct ScreenshotCard: View {
    var url: URL
    @EnvironmentObject private var session: AppSession

    var body: some View {
        HStack(spacing: 8) {
            thumbnail
                .frame(width: 46, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    ScreenshotDragHandle(url: url, source: session.screenshots)
                }
                .onDrag { session.screenshots.itemProvider(for: url) }
            Text("Screenshot")
                .foregroundStyle(.white)
                .font(.system(size: 11, weight: .semibold))
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.15))
        }
    }
}
