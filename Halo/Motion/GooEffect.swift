import AppKit
import CoreImage
import SwiftUI

struct GooBlob: Equatable {
    enum Kind: Equatable {
        case continuousRounded
        case concave(notchWidth: CGFloat, notchHeight: CGFloat, corner: CGFloat, concave: CGFloat)
    }

    var rect: CGRect
    var cornerRadius: CGFloat
    var kind: Kind

    static func pill(_ rect: CGRect) -> GooBlob {
        GooBlob(rect: rect, cornerRadius: min(rect.height, rect.width) / 2, kind: .continuousRounded)
    }
}

/// Metaball mask: solid silhouettes → Gaussian blur → alpha threshold.
/// Runtime path is Core Image (Metal `Metaball.metal` is excluded from the target).
struct GooMask<Content: View>: View {
    var blur: CGFloat
    var threshold: CGFloat
    var smoothness: CGFloat
    var blobs: [GooBlob]
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .mask {
                GooThresholdView(blobs: blobs, blur: blur, threshold: threshold, smoothness: smoothness)
            }
    }
}

enum GooCIFallback {
    static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// `CIGaussianBlur` → `CIColorMatrix` (large alpha gain + threshold bias) → `CIColorClamp`.
    static func apply(to image: NSImage, blur: CGFloat, threshold: CGFloat, smoothness: CGFloat = 0.08) -> NSImage {
        guard let tiff = image.tiffRepresentation, let ci = CIImage(data: tiff) else { return image }
        let radius = max(blur, 0.5)
        let padded = ci.extent.insetBy(dx: -radius * 3, dy: -radius * 3)
        let blurred = ci
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: padded)

        let edge = max(CGFloat(smoothness), 0.02)
        let contrast = max(8, (1.0 / max(threshold * edge, 0.02)) * 4)
        let matrix = CIFilter(name: "CIColorMatrix")
        matrix?.setValue(blurred, forKey: kCIInputImageKey)
        matrix?.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrix?.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
        matrix?.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
        matrix?.setValue(CIVector(x: 0, y: 0, z: 0, w: contrast), forKey: "inputAVector")
        matrix?.setValue(CIVector(x: 0, y: 0, z: 0, w: -threshold * contrast), forKey: "inputBiasVector")
        let boosted = matrix?.outputImage ?? blurred

        let clamped = boosted.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
        ])

        let drawRect = ci.extent
        guard let cg = context.createCGImage(clamped, from: drawRect) else { return image }
        return NSImage(cgImage: cg, size: image.size)
    }
}

struct GooThresholdView: NSViewRepresentable {
    var blobs: [GooBlob]
    var blur: CGFloat
    var threshold: CGFloat
    var smoothness: CGFloat

    func makeNSView(context: Context) -> GooRasterView {
        let view = GooRasterView()
        view.blobs = blobs
        view.blur = blur
        view.threshold = threshold
        view.smoothness = smoothness
        return view
    }

    func updateNSView(_ nsView: GooRasterView, context: Context) {
        nsView.blobs = blobs
        nsView.blur = blur
        nsView.threshold = threshold
        nsView.smoothness = smoothness
        nsView.needsDisplay = true
    }
}

final class GooRasterView: NSView {
    var blobs: [GooBlob] = []
    var blur: CGFloat = 14
    var threshold: CGFloat = 0.5
    var smoothness: CGFloat = 0.08

    override var isOpaque: Bool { false }
    override var wantsUpdateLayer: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.isOpaque = false
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        let silhouette = renderSilhouette()
        let goo = GooCIFallback.apply(to: silhouette, blur: blur, threshold: threshold, smoothness: smoothness)
        goo.draw(in: bounds, from: NSRect(origin: .zero, size: goo.size), operation: .sourceOver, fraction: 1)
    }

    private func renderSilhouette() -> NSImage {
        let drawSize = bounds.size
        let blobs = self.blobs
        return NSImage(size: drawSize, flipped: true) { _ in
            NSColor.white.setFill()
            for blob in blobs {
                let path: Path
                switch blob.kind {
                case .continuousRounded:
                    path = Path(roundedRect: blob.rect, cornerRadius: blob.cornerRadius, style: .continuous)
                case .concave(let notchWidth, let notchHeight, let corner, let concave):
                    path = ConcaveNotchShape(
                        notchWidth: notchWidth,
                        notchHeight: notchHeight,
                        corner: corner,
                        concave: concave
                    ).path(in: blob.rect)
                }
                NSBezierPath(cgPath: path.cgPath).fill()
            }
            return true
        }
    }

}

struct IslandChrome: View {
    var size: CGSize
    var metrics: NotchMetrics
    var state: IslandState
    var glow: Color
    var glowPulse: CGFloat
    var gooDetached: Bool = false

    private var blobs: [GooBlob] {
        var result: [GooBlob] = []
        let bodyRect = CGRect(origin: .zero, size: size)
        switch state {
        case .idle, .compact:
            result.append(.pill(bodyRect))
        case .expanded:
            result.append(
                GooBlob(
                    rect: bodyRect,
                    cornerRadius: 28,
                    kind: .concave(
                        notchWidth: metrics.idleSize.width,
                        notchHeight: metrics.notchHeight,
                        corner: 28,
                        concave: 16
                    )
                )
            )
        }
        if state != .idle {
            let notch = CGRect(
                x: (size.width - metrics.idleSize.width) / 2,
                y: 0,
                width: metrics.idleSize.width,
                height: metrics.idleSize.height
            )
            result.append(.pill(notch))
        }
        if gooDetached {
            let side: CGFloat = 20
            result.append(
                .pill(
                    CGRect(
                        x: size.width - side - 8,
                        y: size.height - side - 4,
                        width: side,
                        height: side
                    )
                )
            )
        }
        return result
    }

    var body: some View {
        let blur = MotionConstants.gooBlur
        let threshold = MotionConstants.gooThreshold
        let smoothness = MotionConstants.gooSmoothness
        return ZStack {
            if state == .idle || state == .compact {
                chromeShape.fill(Color.black)
            } else {
                GooThresholdView(
                    blobs: blobs,
                    blur: blur,
                    threshold: threshold,
                    smoothness: smoothness
                )
                .colorMultiply(Color.black)
                chromeShape
                    .fill(
                        RadialGradient(
                            colors: [glow.opacity(0.45 * glowPulse), .clear],
                            center: .center,
                            startRadius: 4,
                            endRadius: max(size.width, size.height)
                        )
                    )
                    .blendMode(.plusLighter)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private var chromeShape: AnyShape {
        switch state {
        case .idle, .compact:
            AnyShape(RoundedRectangle(cornerRadius: size.height / 2, style: .continuous))
        case .expanded:
            AnyShape(
                ConcaveNotchShape(
                    notchWidth: metrics.idleSize.width,
                    notchHeight: metrics.notchHeight,
                    corner: 28,
                    concave: 16
                )
            )
        }
    }
}

func islandClipShape(size: CGSize, metrics: NotchMetrics, state: IslandState) -> AnyShape {
    switch state {
    case .idle, .compact:
        AnyShape(RoundedRectangle(cornerRadius: size.height / 2, style: .continuous))
    case .expanded:
        AnyShape(
            ConcaveNotchShape(
                notchWidth: metrics.idleSize.width,
                notchHeight: metrics.notchHeight,
                corner: 28,
                concave: 16
            )
        )
    }
}
