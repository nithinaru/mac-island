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

    init(session: AppSession) {
        self.session = session
    }

    func start() {
        guard session.settings.clipboard else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    func poll() {
        let board = NSPasteboard.general
        guard board.changeCount != lastCount else { return }
        lastCount = board.changeCount
        if board.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) == true {
            return
        }
        guard let text = board.string(forType: .string), !text.isEmpty else { return }
        items.insert(ClipboardItem(id: lastCount, text: text, date: Date()), at: 0)
        if items.count > 10 { items.removeLast(items.count - 10) }
    }

    func restore(_ item: ClipboardItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
    }
}

struct ClipboardRingView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(session.clipboard.items) { item in
                    Button {
                        session.clipboard.restore(item)
                    } label: {
                        Text(item.text)
                            .lineLimit(2)
                            .frame(width: 92, height: 48, alignment: .topLeading)
                            .padding(8)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundStyle(.white)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
