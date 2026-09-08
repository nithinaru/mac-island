import AppKit
import CoreGraphics
import Foundation
import SwiftUI

enum IslandState: String, Equatable, CaseIterable {
    case idle
    case compact
    case expanded
}

struct NowPlayingSnapshot: Equatable {
    var persistentID: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var position: TimeInterval
    var isPlaying: Bool
    var rating: Int
    var playedCount: Int
    var bpm: Int
    var volume: Int
    var fileURL: URL?
    var artwork: NSImage?
    var fallbackGradient: [Color]
    var accent: Color
    var nextTracks: [QueueTrack]
}

struct QueueTrack: Equatable, Identifiable {
    var id: String
    var title: String
    var artist: String
}

struct LiveActivityPayload: Equatable, Identifiable, Codable {
    var id: String
    var title: String
    var subtitle: String?
    var progress: Double?
    var symbol: String?
    var timeout: TimeInterval?
}

struct DownloadStatus: Equatable, Identifiable {
    var id: String { url.path }
    var url: URL
    var filename: String
    var fraction: Double?
    var count: Int
}

struct MeetingPayload: Equatable, Identifiable {
    var id: String
    var title: String
    var joinURL: URL?
    var start: Date
}

struct PrivacyStatus: Equatable {
    var micApps: [AudioApp]
    var cameraApps: [String]
    var inputLevel: Float
}

struct AudioApp: Equatable, Identifiable {
    var id: String { bundleID }
    var bundleID: String
    var name: String
    var isOutput: Bool
    var isInput: Bool
}

struct ExclusivityAlert: Equatable, Identifiable {
    var id: String { bundleID }
    var bundleID: String
    var name: String
    var message: String
}

struct OutputDevice: Equatable, Identifiable {
    var id: UInt32
    var name: String
    var isDefault: Bool
}

enum TransientEvent: Equatable {
    case volume(level: Float, muted: Bool)
    case brightness(Float)
    case charging(percent: Int, isCharging: Bool)
    case screenshot(URL)
    case liveActivity(LiveActivityPayload)
    case download(DownloadStatus)
    case meeting(MeetingPayload)
    case clipboard
    case focus(progress: Double)
    case privacy(PrivacyStatus)
    case exclusivity(ExclusivityAlert)
    case devices
    case mixer
    case sleepTimer(remaining: TimeInterval, total: TimeInterval)

    var prefersExpanded: Bool {
        switch self {
        case .clipboard, .devices, .mixer, .meeting:
            return true
        case .volume, .brightness, .charging, .screenshot, .liveActivity, .download, .focus, .privacy, .sleepTimer, .exclusivity:
            return false
        }
    }

    var defaultDuration: TimeInterval? {
        switch self {
        case .volume, .brightness:
            return 1.6
        case .charging:
            return 3.2
        case .screenshot:
            return 45
        case .liveActivity(let payload):
            return payload.timeout
        case .download:
            return nil
        case .meeting:
            return 120
        case .clipboard, .devices, .mixer:
            return nil
        case .exclusivity:
            return 2.8
        case .focus, .privacy, .sleepTimer:
            return nil
        }
    }
}

enum EnforcementMode: String, Codable, CaseIterable {
    case enforce
    case displayOnly
}

struct WaveformCache: Equatable {
    var persistentID: String
    var peaks: [Float]
    var sampleCount: Int
}

struct NotchMetrics: Equatable {
    var screenFrame: CGRect
    var visibleFrame: CGRect
    var hasNotch: Bool
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var idleSize: CGSize
    var compactSize: CGSize
    var expandedSize: CGSize
    var windowSize: CGSize
    var windowOrigin: CGPoint
    var isFallbackPill: Bool

    static let fallbackNotch = CGSize(width: 160, height: 32)
}
