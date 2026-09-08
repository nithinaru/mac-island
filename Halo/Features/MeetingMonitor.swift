import AppKit
import Combine
import EventKit
import Foundation
import SwiftUI

@MainActor
final class MeetingMonitor: ObservableObject {
    unowned let session: AppSession
    private let store = EKEventStore()
    @Published var upcoming: MeetingPayload?

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        guard session.settings.meetings else { return }
        Task {
            do {
                try await store.requestFullAccessToEvents()
                scan()
            } catch {
                return
            }
        }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    func scan() {
        let start = Date()
        let end = start.addingTimeInterval(60 * 60)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        guard let event = events.sorted(by: { $0.startDate < $1.startDate }).first else { return }
        let remaining = event.startDate.timeIntervalSinceNow
        guard remaining > 0, remaining <= 120 else { return }
        let payload = MeetingPayload(
            id: event.eventIdentifier,
            title: event.title ?? "Meeting",
            joinURL: event.url ?? Self.extractURL(from: event.notes),
            start: event.startDate
        )
        upcoming = payload
        session.island.post(.meeting(payload), duration: remaining)
    }

    func join(_ payload: MeetingPayload) {
        if let url = payload.joinURL {
            NSWorkspace.shared.open(url)
        }
    }

    static func extractURL(from notes: String?) -> URL? {
        guard let notes else { return nil }
        let pattern = #"https?://[^\s]+(zoom\.us|meet\.google\.com|teams\.microsoft\.com)[^\s]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: notes, range: NSRange(notes.startIndex..., in: notes)),
              let range = Range(match.range, in: notes)
        else { return nil }
        return URL(string: String(notes[range]))
    }
}

struct MeetingJoinView: View {
    var payload: MeetingPayload
    @EnvironmentObject private var session: AppSession

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(payload.title).foregroundStyle(.white).lineLimit(1)
                Text(payload.start, style: .time).foregroundStyle(.white.opacity(0.6)).font(.caption)
            }
            Spacer()
            Button("Join") {
                session.meetings.join(payload)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.white.opacity(0.16), in: Capsule())
            .foregroundStyle(.white)
        }
    }
}
