import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppMixerController: ObservableObject {
    unowned let session: AppSession
    private var cancellables: Set<AnyCancellable> = []

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        session.exclusivity.monitor.$processes
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var apps: [AudioApp] {
        session.exclusivity.monitor.outputting
    }

    func pause(_ app: AudioApp) {
        OffenderLevers.pause(app)
    }

    func reveal(_ app: AudioApp) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
        if let front = running.first {
            front.activate()
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

struct AppMixerView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        AppMixerList(monitor: session.exclusivity.monitor)
            .environmentObject(session)
    }
}

private struct AppMixerList: View {
    @EnvironmentObject private var session: AppSession
    @ObservedObject var monitor: AudioProcessMonitor

    var body: some View {
        let apps = monitor.outputting
        VStack(alignment: .leading, spacing: 8) {
            Text("Apps producing audio")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text("Not per-app volume — macOS has no public per-app volume API.")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
            if apps.isEmpty {
                Text("Nothing is outputting audio right now.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                ForEach(apps) { app in
                    HStack(spacing: 8) {
                        Text(app.name)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button("Pause") { session.mixer.pause(app) }
                        Button("Bring to Front") { session.mixer.reveal(app) }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .font(.system(size: 12))
                }
            }
            Text("Pause and Bring to Front only. This is not a volume mixer and does not install a virtual audio driver.")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
