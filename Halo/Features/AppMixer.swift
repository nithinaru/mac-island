import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppMixerController: ObservableObject {
    unowned let session: AppSession

    init(session: AppSession) {
        self.session = session
    }

    func start() {}

    var apps: [AudioApp] {
        session.exclusivity.monitor.outputting
    }

    func pause(_ app: AudioApp) {
        OffenderLevers.pause(app)
    }

    func reveal(_ app: AudioApp) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

struct AppMixerView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Playing audio")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            ForEach(session.mixer.apps) { app in
                HStack {
                    Text(app.name).foregroundStyle(.white)
                    Spacer()
                    Button("Pause") { session.mixer.pause(app) }
                    Button("Show") { session.mixer.reveal(app) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .font(.system(size: 12))
            }
            Text("Pause only — macOS has no public per-app volume API.")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}
