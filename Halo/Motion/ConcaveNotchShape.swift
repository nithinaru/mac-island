import SwiftUI

/// Expanded-island silhouette: a wide panel whose top edge meets the physical
/// notch with *outward* quarter-arcs (inverse of a rounded-rect corner) so the
/// panel reads as growing out of the notch rather than hanging below it.
struct ConcaveNotchShape: Shape {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var corner: CGFloat
    var concave: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(notchWidth, notchHeight), AnimatablePair(corner, concave)) }
        set {
            notchWidth = newValue.first.first
            notchHeight = newValue.first.second
            corner = newValue.second.first
            concave = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let notchW = min(max(notchWidth, 0), rect.width)
        let notchH = min(max(notchHeight, 0), rect.height)
        let notchLeading = rect.midX - notchW / 2
        let notchTrailing = rect.midX + notchW / 2

        let wing = max(0, (rect.width - notchW) / 2)
        let bodyHeight = max(0, rect.height - notchH)
        let outer = min(corner, wing, bodyHeight / 2, rect.height / 2)
        let cave = min(concave, wing * 0.9, notchH, outer == 0 ? concave : outer)

        if notchH < 0.5 || cave < 0.5 || wing < cave {
            let radius = min(max(outer, min(rect.height, rect.width) / 2), rect.height / 2)
            path.addPath(Path(roundedRect: rect, cornerRadius: radius, style: .continuous))
            return path
        }

        // Top of notch (flush with the screen / hardware cutout).
        path.move(to: CGPoint(x: notchLeading, y: rect.minY))
        path.addLine(to: CGPoint(x: notchTrailing, y: rect.minY))

        // Right wall of the notch, then an outward quarter-arc into the panel.
        path.addLine(to: CGPoint(x: notchTrailing, y: rect.minY + notchH - cave))
        path.addArc(
            center: CGPoint(x: notchTrailing, y: rect.minY + notchH),
            radius: cave,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Panel top-right continuous corner, down, bottom, up the left side.
        path.addLine(to: CGPoint(x: rect.maxX - outer, y: rect.minY + notchH))
        addContinuousCorner(
            to: &path,
            start: CGPoint(x: rect.maxX - outer, y: rect.minY + notchH),
            corner: CGPoint(x: rect.maxX, y: rect.minY + notchH),
            end: CGPoint(x: rect.maxX, y: rect.minY + notchH + outer),
            radius: outer
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - outer))
        addContinuousCorner(
            to: &path,
            start: CGPoint(x: rect.maxX, y: rect.maxY - outer),
            corner: CGPoint(x: rect.maxX, y: rect.maxY),
            end: CGPoint(x: rect.maxX - outer, y: rect.maxY),
            radius: outer
        )
        path.addLine(to: CGPoint(x: rect.minX + outer, y: rect.maxY))
        addContinuousCorner(
            to: &path,
            start: CGPoint(x: rect.minX + outer, y: rect.maxY),
            corner: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.minX, y: rect.maxY - outer),
            radius: outer
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + notchH + outer))
        addContinuousCorner(
            to: &path,
            start: CGPoint(x: rect.minX, y: rect.minY + notchH + outer),
            corner: CGPoint(x: rect.minX, y: rect.minY + notchH),
            end: CGPoint(x: rect.minX + outer, y: rect.minY + notchH),
            radius: outer
        )

        // Panel top-left → outward quarter-arc onto the notch's left wall.
        path.addLine(to: CGPoint(x: notchLeading - cave, y: rect.minY + notchH))
        path.addArc(
            center: CGPoint(x: notchLeading, y: rect.minY + notchH),
            radius: cave,
            startAngle: .degrees(180),
            endAngle: .degrees(-90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: notchLeading, y: rect.minY))
        path.closeSubpath()
        return path
    }

    /// Squircle-ish corner (same family as `RoundedRectangle(..., style: .continuous)`).
    private func addContinuousCorner(
        to path: inout Path,
        start: CGPoint,
        corner: CGPoint,
        end: CGPoint,
        radius: CGFloat
    ) {
        let pull = radius * 0.55
        let c1 = CGPoint(
            x: start.x + (corner.x - start.x) * (pull / max(radius, 0.001)),
            y: start.y + (corner.y - start.y) * (pull / max(radius, 0.001))
        )
        let c2 = CGPoint(
            x: end.x + (corner.x - end.x) * (pull / max(radius, 0.001)),
            y: end.y + (corner.y - end.y) * (pull / max(radius, 0.001))
        )
        path.addCurve(to: end, control1: c1, control2: c2)
    }
}
