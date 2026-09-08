import AppKit
import Combine
import SwiftUI

struct ClipboardItem: Identifiable, Equatable {
    var id: Int
    var text: String
    var date: Date
}

@MainActor
final class ClipboardRing: ObservableObject {
    unowned let session: AppSession
    @Published var items: [ClipboardItem] = []
    private var lastCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let maxItems = 10
    private static let pollInterval: TimeInterval = 0.3

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        timer?.invalidate()
        timer = nil
        guard session.settings.clipboard else { return }
        lastCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func poll() {
        let board = NSPasteboard.general
        let count = board.changeCount
        guard count != lastCount else { return }
        lastCount = count
        guard !isConcealed(board) else { return }
        guard let text = board.string(forType: .string), !text.isEmpty else { return }
        if items.first?.text == text { return }
        items.insert(ClipboardItem(id: count, text: text, date: Date()), at: 0)
        if items.count > Self.maxItems {
            items.removeLast(items.count - Self.maxItems)
        }
        session.island.post(.clipboard, duration: 4.5)
    }

    func restore(_ item: ClipboardItem) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(item.text, forType: .string)
        lastCount = board.changeCount
        if let index = items.firstIndex(of: item) {
            items.remove(at: index)
            items.insert(item, at: 0)
        }
    }

    private func isConcealed(_ board: NSPasteboard) -> Bool {
        if board.types?.contains(Self.concealedType) == true { return true }
        if board.availableType(from: [Self.concealedType]) != nil { return true }
        if board.data(forType: Self.concealedType) != nil { return true }
        return false
    }
}

struct ClipboardRingView: View {
    @EnvironmentObject private var session: AppSession
    @State private var hovering = false

    var body: some View {
        let cards = Array(session.clipboard.items.prefix(10))
        let spread = hovering || session.island.visualState == .expanded
        HStack(spacing: spread ? 8 : -64) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, item in
                Button {
                    session.clipboard.restore(item)
                } label: {
                    Text(item.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(width: 96, height: 52, alignment: .topLeading)
                        .padding(8)
                        .background(
                            Color.white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .foregroundStyle(.white)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                }
                .buttonStyle(.plain)
                .rotationEffect(.degrees(spread ? 0 : Double(index) * 3.5 - 6))
                .offset(y: spread ? 0 : CGFloat(index) * 1.5)
                .zIndex(Double(cards.count - index))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: spread)
        .onHover { hovering = $0 }
    }
}
