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
        listener?.cancel()
        listener = nil
        guard session.settings.liveActivities else { return }

        let portNumber = UInt16(session.settings.liveActivityPort)
        let port = NWEndpoint.Port(rawValue: portNumber > 0 ? portNumber : 18473) ?? 18473
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: port
        )

        guard let listener = try? NWListener(using: parameters, on: port) else { return }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            let queue = DispatchQueue(label: "halo.live-activity.connection")
            connection.start(queue: queue)
            Self.read(connection: connection, buffer: Data()) { body, method in
                Task { @MainActor in
                    let allowed = self?.session.settings.liveActivities == true
                    let status: Int
                    let ok: Bool
                    if method != "POST" {
                        ok = false
                        status = 405
                    } else if allowed, self?.handle(body) == true {
                        ok = true
                        status = 200
                    } else {
                        ok = false
                        status = 400
                    }
                    let id = (try? JSONDecoder().decode(LiveActivityPayload.self, from: body))?.id
                    Self.respond(connection: connection, ok: ok, id: id, status: status)
                }
            }
        }
        listener.start(queue: .main)
    }

    @discardableResult
    func handle(_ data: Data) -> Bool {
        guard session.settings.liveActivities else { return false }
        guard let payload = try? JSONDecoder().decode(LiveActivityPayload.self, from: data) else { return false }
        activities[payload.id] = payload
        session.island.post(.liveActivity(payload), duration: payload.timeout)
        return true
    }

    nonisolated static func read(connection: NWConnection, complete: @escaping (Data) -> Void) {
        read(connection: connection, buffer: Data()) { body, _ in
            complete(body)
        }
    }

    nonisolated static func read(connection: NWConnection, buffer: Data, complete: @escaping (Data, String) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64_000) { chunk, _, isComplete, error in
            var next = buffer
            if let chunk, !chunk.isEmpty {
                next.append(chunk)
            }
            if let parsed = Self.parseHTTP(next) {
                complete(parsed.body, parsed.method)
                return
            }
            if isComplete || error != nil {
                complete(Self.body(from: next), "POST")
                return
            }
            Self.read(connection: connection, buffer: next, complete: complete)
        }
    }

    nonisolated static func body(from data: Data) -> Data {
        parseHTTP(data)?.body ?? {
            guard let text = String(data: data, encoding: .utf8) else { return data }
            if let range = text.range(of: "\r\n\r\n") {
                return Data(text[range.upperBound...].utf8)
            }
            if let range = text.range(of: "\n\n") {
                return Data(text[range.upperBound...].utf8)
            }
            return data
        }()
    }

    nonisolated static func parseHTTP(_ data: Data) -> (method: String, body: Data)? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let headerEnd: String.Index
        let separatorLength: Int
        if let range = text.range(of: "\r\n\r\n") {
            headerEnd = range.lowerBound
            separatorLength = 4
        } else if let range = text.range(of: "\n\n") {
            headerEnd = range.lowerBound
            separatorLength = 2
        } else {
            return nil
        }

        let headerText = String(text[..<headerEnd])
        let lines = headerText.split(whereSeparator: { $0 == "\n" }).map {
            $0.hasSuffix("\r") ? String($0.dropLast()) : String($0)
        }
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        let method = parts.first.map(String.init)?.uppercased() ?? "GET"

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let bodyStart = text.index(headerEnd, offsetBy: separatorLength)
        let body = Data(text[bodyStart...].utf8)
        if let lengthText = headers["content-length"], let length = Int(lengthText) {
            guard body.count >= length else { return nil }
            return (method, Data(body.prefix(length)))
        }
        return (method, body)
    }

    nonisolated static func respond(connection: NWConnection, ok: Bool, id: String?, status: Int) {
        var object: [String: Any] = ["ok": ok]
        if let id { object["id"] = id }
        let payload = (try? JSONSerialization.data(withJSONObject: object)) ?? Data(#"{"ok":false}"#.utf8)
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 405: reason = "Method Not Allowed"
        default: reason = "Error"
        }
        var header = "HTTP/1.1 \(status) \(reason)\r\n"
        header += "Content-Type: application/json\r\n"
        header += "Content-Length: \(payload.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(payload)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
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
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                if let progress = payload.progress {
                    GeometryReader { geo in
                        Capsule()
                            .fill(.white.opacity(0.15))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(.white)
                                    .frame(width: geo.size.width * min(1, max(0, progress)))
                            }
                    }
                    .frame(height: 4)
                }
            }
        }
    }
}
