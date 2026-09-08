import SwiftUI

enum MotionConstants {
    static var gooBlur: CGFloat = 14
    static var gooThreshold: CGFloat = 0.5
    static var gooSmoothness: CGFloat = 0.08
    static var extraBounce: Double = 0.14
    static var compactDuration: Double = 0.32
    static var expandResponse: Double = 0.42
    static var expandDamping: Double = 0.78
    static var contentDuration: Double = 0.25
    static var colorBleedDuration: Double = 0.8
    static var hoverSlop: CGFloat = 10

    static var stateSpring: Animation {
        .snappy(duration: compactDuration, extraBounce: extraBounce)
    }

    static var expandSpring: Animation {
        .spring(response: expandResponse, dampingFraction: expandDamping)
    }

    static var contentSpring: Animation {
        .smooth(duration: contentDuration)
    }
}

enum GeometryIDs {
    static let art = "island.art"
    static let title = "island.title"
    static let waveform = "island.waveform"
    static let pill = "island.pill"
}
