import SwiftUI

/// Compact Dynamic Island layout: left wing · hardware camera · right wing.
/// The center is empty so the physical notch hides it, like iOS / Notchy.
struct CompactWingLayout<Left: View, Right: View>: View {
    var notchWidth: CGFloat
    var wingPadding: CGFloat = 7
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    var body: some View {
        HStack(spacing: 0) {
            left()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.leading, wingPadding)
            Color.clear
                .frame(width: max(notchWidth, 0))
                .accessibilityHidden(true)
            right()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.trailing, wingPadding)
        }
    }
}
