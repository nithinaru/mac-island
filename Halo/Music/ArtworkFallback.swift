import AppKit
import SwiftUI

enum ArtworkFallback {
    /// Deterministic album field: same artist+album always yields the same hues.
    static func gradient(artist: String, album: String) -> [Color] {
        let seed = "\(artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))|\(album.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
        let hash = fnv1a64(seed.isEmpty ? "halo|untitled" : seed)

        let hueA = Double(hash % 360) / 360.0
        let span = 0.30 + Double((hash >> 9) % 45) / 100.0
        let hueB = wrapHue(hueA + span)
        let hueMid = wrapHue(hueA + span * 0.42)

        let satA = 0.64 + Double((hash >> 18) % 26) / 100.0
        let satB = 0.52 + Double((hash >> 26) % 28) / 100.0
        let satMid = 0.70 + Double((hash >> 34) % 18) / 100.0

        let briA = 0.82 + Double((hash >> 40) % 14) / 100.0
        let briMid = 0.58 + Double((hash >> 46) % 16) / 100.0
        let briB = 0.22 + Double((hash >> 52) % 16) / 100.0
        let briGlow = 0.92 + Double((hash >> 56) % 8) / 100.0

        return [
            Color(hue: hueA, saturation: satA, brightness: min(briGlow, 1), opacity: 1),
            Color(hue: hueMid, saturation: satMid, brightness: briMid, opacity: 1),
            Color(hue: hueB, saturation: satB, brightness: max(briB, 0.18), opacity: 1),
            Color(hue: wrapHue(hueA + 0.08), saturation: min(satA + 0.06, 0.92), brightness: 0.34, opacity: 1)
        ]
    }

    static func accent(fromGradient colors: [Color]) -> Color {
        colors.first ?? Color(hue: 0.62, saturation: 0.62, brightness: 0.9)
    }

    private static func wrapHue(_ value: Double) -> Double {
        let wrapped = value.truncatingRemainder(dividingBy: 1)
        return wrapped < 0 ? wrapped + 1 : wrapped
    }

    private static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}

enum ColorBleed {
    static func accent(from image: NSImage?, fallback: Color) -> Color {
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return fallback
        }
        return dominantColor(cgImage: cg) ?? fallback
    }

    static func dominantColor(cgImage: CGImage) -> Color? {
        let width = 32
        let height = 32
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        ctx.interpolationQuality = .low
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        var bestSat: CGFloat = -1
        var best = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0))
        for i in stride(from: 0, to: width * height * 4, by: 4) {
            let a = CGFloat(ptr[i + 3]) / 255
            guard a > 0.4 else { continue }
            var r = CGFloat(ptr[i]) / 255
            var g = CGFloat(ptr[i + 1]) / 255
            var b = CGFloat(ptr[i + 2]) / 255
            if a < 1 {
                r /= a
                g /= a
                b /= a
            }
            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let sat = maxC == 0 ? 0 : (maxC - minC) / maxC
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            guard luminance > 0.12 else { continue }
            let score = sat * 0.78 + min(luminance, 1) * 0.22
            if score > bestSat {
                bestSat = score
                best = (r, g, b)
            }
        }
        guard bestSat >= 0 else { return nil }
        return contrastOnBlack(r: best.r, g: best.g, b: best.b)
    }

    private static func contrastOnBlack(r: CGFloat, g: CGFloat, b: CGFloat) -> Color {
        var r = min(max(r, 0), 1)
        var g = min(max(g, 0), 1)
        var b = min(max(b, 0), 1)
        var luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if luminance < 0.22 {
            let lift = (0.22 - luminance) / 0.22 * 0.42
            r = r + (1 - r) * lift
            g = g + (1 - g) * lift
            b = b + (1 - b) * lift
            luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        if luminance < 0.18 {
            return Color(hue: 0.62, saturation: 0.55, brightness: 0.92)
        }
        return Color(red: r, green: g, blue: b)
    }
}
