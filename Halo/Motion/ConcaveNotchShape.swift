import SwiftUI

struct ConcaveNotchShape: Shape {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var corner: CGFloat
    var concave: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(notchWidth, notchHeight) }
        set {
            notchWidth = newValue.first
            notchHeight = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(corner, rect.height / 2)
        let cave = min(concave, radius)
        let notchLeading = rect.midX - notchWidth / 2
        let notchTrailing = rect.midX + notchWidth / 2

        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: notchTrailing + cave, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: notchTrailing, y: rect.maxY - cave),
            control1: CGPoint(x: notchTrailing, y: rect.maxY),
            control2: CGPoint(x: notchTrailing, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: notchTrailing, y: rect.maxY - notchHeight + cave))
        path.addQuadCurve(
            to: CGPoint(x: notchTrailing - cave, y: rect.maxY - notchHeight),
            control: CGPoint(x: notchTrailing, y: rect.maxY - notchHeight)
        )
        path.addLine(to: CGPoint(x: notchLeading + cave, y: rect.maxY - notchHeight))
        path.addQuadCurve(
            to: CGPoint(x: notchLeading, y: rect.maxY - notchHeight + cave),
            control: CGPoint(x: notchLeading, y: rect.maxY - notchHeight)
        )
        path.addLine(to: CGPoint(x: notchLeading, y: rect.maxY - cave))
        path.addCurve(
            to: CGPoint(x: notchLeading - cave, y: rect.maxY),
            control1: CGPoint(x: notchLeading, y: rect.maxY),
            control2: CGPoint(x: notchLeading, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
