import Combine
import Foundation
import SwiftUI

@MainActor
final class PrivacyMonitor: ObservableObject {
    unowned let session: AppSession
    @Published var status = PrivacyStatus(micApps: [], cameraApps: [], inputLevel: 0)

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        guard session.settings.privacy else { return }
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        let mic = session.exclusivity.monitor.inputting
        status = PrivacyStatus(micApps: mic, cameraApps: [], inputLevel: session.processTap.level)
        if !mic.isEmpty {
            session.island.post(.privacy(status))
        }
    }
}

struct PrivacyView: View {
    var status: PrivacyStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill").foregroundStyle(.green)
            VStack(alignment: .leading) {
                Text(status.micApps.map(\.name).joined(separator: ", "))
                    .foregroundStyle(.white)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Capsule().fill(.white.opacity(0.15)).frame(width: 72, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule().fill(.green).frame(width: 72 * CGFloat(status.inputLevel))
                    }
            }
        }
    }
}
