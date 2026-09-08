import AppKit
import SwiftUI

enum ArtworkFallback {
    static func gradient(artist: String, album: String) -> [Color] {
        let seed = "\(artist)|\(album)"
        var hash: UInt64 = 5381
        for byte in seed.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let hueA = Double(hash % 360) / 360.0
        let hueB = Double((hash >> 9) % 360) / 360.0
        return [
            Color(hue: hueA, saturation: 0.72, brightness: 0.86),
            Color(hue: hueB, saturation: 0.58, brightness: 0.42)
        ]
    }
}

enum ColorBleed {
    static func accent(from image: NSImage?) -> Color {
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return Color(hue: 0.62, saturation: 0.45, brightness: 0.9)
        }
        return dominantColor(cgImage: cg)
    }

    static func dominantColor(cgImage: CGImage) -> Color {
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
            return .white
        }
        ctx.interpolationQuality = .low
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { return .white }
        let ptr = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var best = (sat: CGFloat(0), color: Color.white)
        for i in stride(from: 0, to: width * height * 4, by: 16) {
            let r = CGFloat(ptr[i]) / 255
            let g = CGFloat(ptr[i + 1]) / 255
            let b = CGFloat(ptr[i + 2]) / 255
            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let sat = maxC == 0 ? 0 : (maxC - minC) / maxC
            if sat > best.sat && maxC > 0.18 {
                best = (sat, Color(red: r, green: g, blue: b))
            }
        }
        return best.color
    }
}
