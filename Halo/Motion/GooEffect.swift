import AppKit
import CoreImage
import SwiftUI

struct GooMask<Content: View>: View {
    var blur: CGFloat
    var threshold: CGFloat
    var smoothness: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .compositingGroup()
            .blur(radius: blur * 0.35)
            .contrast(1.0 + (1.0 - threshold) * 2.4)
            .saturation(1.05)
            .overlay {
                Rectangle()
                    .fill(.white.opacity(0.001))
                    .allowsHitTesting(false)
            }
    }
}

enum GooCIFallback {
    static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func apply(to image: NSImage, blur: CGFloat, threshold: CGFloat) -> NSImage {
        guard let tiff = image.tiffRepresentation, let ci = CIImage(data: tiff) else { return image }
        let blurred = ci.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blur])
        let matrix = CIFilter(name: "CIColorMatrix")
        matrix?.setValue(blurred, forKey: kCIInputImageKey)
        matrix?.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrix?.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
        matrix?.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
        matrix?.setValue(CIVector(x: 0, y: 0, z: 0, w: 8), forKey: "inputAVector")
        let boosted = matrix?.outputImage ?? blurred
        let clamped = boosted.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: threshold),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
        ])
        guard let cg = context.createCGImage(clamped, from: ci.extent) else { return image }
        return NSImage(cgImage: cg, size: image.size)
    }
}

struct IslandChrome: View {
    var size: CGSize
    var metrics: NotchMetrics
    var state: IslandState
    var glow: Color
    var glowPulse: CGFloat

    var body: some View {
        let shape = chromeShape
        return ZStack {
            shape.fill(Color.black)
            shape.fill(
                RadialGradient(
                    colors: [glow.opacity(0.45 * glowPulse), .clear],
                    center: .center,
                    startRadius: 4,
                    endRadius: max(size.width, size.height)
                )
            )
        }
        .frame(width: size.width, height: size.height)
    }

    private var chromeShape: AnyShape {
        switch state {
        case .idle, .compact:
            AnyShape(RoundedRectangle(cornerRadius: size.height / 2, style: .continuous))
        case .expanded:
            AnyShape(ConcaveNotchShape(
                notchWidth: metrics.idleSize.width,
                notchHeight: metrics.notchHeight,
                corner: 28,
                concave: 16
            ))
        }
    }
}
