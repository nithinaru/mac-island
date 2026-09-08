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
    private var sequenceTask: Task<Void, Never>?
    private var loginHold = true

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self else { return }
            self.loginHold = false
            self.recomputeState()
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
        apply(targetState())
    }

    private func targetState() -> IslandState {
        if isHovering {
            return .expanded
        }
        if loginHold {
            return .idle
        }
        if let transient, transient.prefersExpanded {
            return .expanded
        }
        if transient != nil {
            return .compact
        }
        if session.music.snapshot?.isPlaying == true {
            return .compact
        }
        return .idle
    }

    private func apply(_ next: IslandState) {
        let detached = shouldDetachGoo(for: next)
        guard next != visualState else {
            if detached != gooDetached {
                withAnimation(MotionConstants.contentSpring) {
                    gooDetached = detached
                }
            }
            return
        }

        sequenceTask?.cancel()
        sequenceTask = nil

        switch (visualState, next) {
        case (.idle, .expanded):
            withAnimation(MotionConstants.stateSpring) {
                visualState = .compact
                gooDetached = shouldDetachGoo(for: .compact)
            }
            sequenceTowardTarget()
        case (.expanded, .idle):
            withAnimation(MotionConstants.expandSpring) {
                visualState = .compact
                gooDetached = shouldDetachGoo(for: .compact)
            }
            sequenceTowardTarget()
        case (.idle, .compact), (.compact, .idle):
            withAnimation(MotionConstants.stateSpring) {
                visualState = next
                gooDetached = detached
            }
        case (.compact, .expanded), (.expanded, .compact):
            withAnimation(MotionConstants.expandSpring) {
                visualState = next
                gooDetached = detached
            }
        case (.idle, .idle), (.compact, .compact), (.expanded, .expanded):
            withAnimation(MotionConstants.contentSpring) {
                gooDetached = detached
            }
        }
    }

    private func shouldDetachGoo(for state: IslandState) -> Bool {
        guard let transient else { return false }
        switch state {
        case .idle:
            return false
        case .compact:
            return !transient.prefersExpanded
        case .expanded:
            return false
        }
    }

    /// Commits Compact as its own frame, then continues toward the latest target.
    /// Springs own the motion; this delay is only so Idle↔Expanded never skips Compact.
    private func sequenceTowardTarget() {
        let nanos = UInt64(max(0.06, MotionConstants.compactDuration * 0.28) * 1_000_000_000)
        sequenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.apply(self?.targetState() ?? .idle)
            }
        }
    }
}
