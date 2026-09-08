import AppKit
import Combine
import SwiftUI

@MainActor
final class IslandController: ObservableObject {
    unowned let session: AppSession

    @Published var visualState: IslandState = .idle
    @Published var isHovering = false
    @Published var transient: TransientEvent?
    @Published var gooDetached: Bool = false

    private var dismissTask: Task<Void, Never>?
    private var loginHold = true

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self?.loginHold = false
        }
    }

    func setHover(_ hovering: Bool) {
        isHovering = hovering
        recomputeState()
    }

    func post(_ event: TransientEvent, duration: TimeInterval? = nil) {
        dismissTask?.cancel()
        transient = event
        recomputeState()
        let timeout = duration ?? event.defaultDuration
        if let timeout {
            dismissTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if self?.transient == event {
                        self?.transient = nil
                        self?.recomputeState()
                    }
                }
            }
        }
    }

    func clearTransient() {
        dismissTask?.cancel()
        transient = nil
        recomputeState()
    }

    func recomputeState() {
        let next: IslandState
        if isHovering {
            next = .expanded
        } else if let transient, transient.prefersExpanded {
            next = .expanded
        } else if transient != nil {
            next = .compact
        } else if session.music.snapshot?.isPlaying == true {
            next = .compact
        } else {
            next = .idle
        }
        apply(next)
    }

    private func apply(_ next: IslandState) {
        guard next != visualState else { return }
        let animation: Animation
        switch (visualState, next) {
        case (.idle, .compact), (.compact, .idle):
            animation = MotionConstants.stateSpring
        case (.compact, .expanded), (.expanded, .compact):
            animation = MotionConstants.expandSpring
        case (.idle, .expanded):
            withAnimation(MotionConstants.stateSpring) { visualState = .compact }
            withAnimation(MotionConstants.expandSpring) { visualState = .expanded }
            return
        case (.expanded, .idle):
            withAnimation(MotionConstants.expandSpring) { visualState = .compact }
            withAnimation(MotionConstants.stateSpring) { visualState = .idle }
            return
        default:
            animation = MotionConstants.contentSpring
        }
        withAnimation(animation) {
            visualState = next
        }
    }
}
