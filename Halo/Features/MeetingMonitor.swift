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
    private var announcedID: String?
    private var changeObserver: NSObjectProtocol?

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        guard session.settings.meetings else { return }
        Task { await requestAccessAndScan() }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    private func requestAccessAndScan() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            scan()
        case .authorized:
            scan()
        case .notDetermined:
            do {
                let granted = try await store.requestFullAccessToEvents()
                if granted {
                    scan()
                }
            } catch {
                return
            }
        case .denied, .restricted, .writeOnly:
            return
        @unknown default:
            return
        }
    }

    func scan() {
        guard session.settings.meetings else { return }
        let access = EKEventStore.authorizationStatus(for: .event)
        switch access {
        case .fullAccess, .authorized:
            break
        case .notDetermined, .denied, .restricted, .writeOnly:
            return
        @unknown default:
            return
        }

        let start = Date()
        let end = start.addingTimeInterval(60 * 60)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        guard let event = events.first(where: { candidate in
            let remaining = candidate.startDate.timeIntervalSinceNow
            return remaining > 0 && remaining <= 120
        }) else {
            if let announcedID, upcoming?.id == announcedID {
                if case .meeting = session.island.transient {
                    session.island.clearTransient()
                }
                upcoming = nil
                self.announcedID = nil
            }
            return
        }

        let remaining = event.startDate.timeIntervalSinceNow
        let payload = MeetingPayload(
            id: event.eventIdentifier,
            title: event.title ?? "Meeting",
            joinURL: event.url ?? Self.extractURL(from: event.notes),
            start: event.startDate
        )
        upcoming = payload
        guard announcedID != payload.id else { return }
        announcedID = payload.id
        session.island.post(.meeting(payload), duration: remaining)
    }

    func join(_ payload: MeetingPayload) {
        if let url = payload.joinURL {
            NSWorkspace.shared.open(url)
        }
    }

    static func extractURL(from notes: String?) -> URL? {
        guard let notes, !notes.isEmpty else { return nil }
        let pattern = #"https?://[^\s<>\"]+(zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com)[^\s<>\"]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: notes, range: NSRange(notes.startIndex..., in: notes)),
              let range = Range(match.range, in: notes)
        else { return nil }
        var raw = String(notes[range])
        while let last = raw.last, ".,);]>".contains(last) {
            raw.removeLast()
        }
        return URL(string: raw)
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
            if payload.joinURL != nil {
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
}
