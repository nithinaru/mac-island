import Combine
import Foundation
import Network
import SwiftUI

@MainActor
final class LiveActivityServer: ObservableObject {
    unowned let session: AppSession
    @Published var activities: [String: LiveActivityPayload] = [:]
    private var listener: NWListener?

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        guard session.settings.liveActivities else { return }
        let port = NWEndpoint.Port(rawValue: UInt16(session.settings.liveActivityPort)) ?? 18473
        listener = try? NWListener(using: .tcp, on: port)
        listener?.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global())
            Self.read(connection: connection) { data in
                Task { @MainActor in
                    self?.handle(data)
                }
            }
        }
        listener?.start(queue: .main)
    }

    func handle(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(LiveActivityPayload.self, from: data) else { return }
        activities[payload.id] = payload
        session.island.post(.liveActivity(payload), duration: payload.timeout)
    }

    nonisolated static func read(connection: NWConnection, complete: @escaping (Data) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64_000) { data, _, _, _ in
            if let data, !data.isEmpty {
                complete(Self.body(from: data))
            }
        }
    }

    nonisolated static func body(from data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8) else { return data }
        if let range = text.range(of: "\r\n\r\n") {
            return Data(text[range.upperBound...].utf8)
        }
        return data
    }
}

struct LiveActivityView: View {
    var payload: LiveActivityPayload

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: payload.symbol ?? "dot.radiowaves.left.and.right")
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 4) {
                Text(payload.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                if let subtitle = payload.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                if let progress = payload.progress {
                    Capsule().fill(.white.opacity(0.15)).frame(height: 4)
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white).frame(width: 80 * progress)
                        }
                }
            }
        }
    }
}
