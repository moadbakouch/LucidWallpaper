import Foundation
import AVFoundation

/// How a video wallpaper fills its screen. Persisted per wallpaper.
struct VideoScaling: Codable, Hashable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case fill      // crop to fill (no bars) — resizeAspectFill
        case fit       // letterbox to show the whole frame — resizeAspect
        case stretch   // distort to exactly fit — resize

        var id: String { rawValue }

        var label: String {
            switch self {
            case .fill: return "Fill"
            case .fit: return "Fit"
            case .stretch: return "Stretch"
            }
        }

        var gravity: AVLayerVideoGravity {
            switch self {
            case .fill: return .resizeAspectFill
            case .fit: return .resizeAspect
            case .stretch: return .resize
            }
        }
    }

    var mode: Mode = .fill
    var zoom: Double = 1.0   // 1.0…2.0, applied as a center-anchored scale

    static let `default` = VideoScaling(mode: .fill, zoom: 1.0)
}
