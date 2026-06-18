import Foundation

/// Auto-rotates the wallpaper through the library on a timer (sequential or shuffle),
/// using crossfade transitions. Off by default.
@MainActor
final class PlaylistController {
    private let model: AppModel
    private var timer: Timer?

    var isEnabled = false { didSet { reschedule() } }
    var intervalSeconds: TimeInterval = 600 { didSet { reschedule() } }
    var shuffle = false

    init(model: AppModel) {
        self.model = model
    }

    func reschedule() {
        timer?.invalidate()
        timer = nil
        guard isEnabled, intervalSeconds > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func advance() {
        guard model.items.count > 1 else { return }
        if shuffle {
            model.randomWallpaper(crossfade: true)
        } else {
            model.cycleWallpaper(by: 1, crossfade: true)
        }
    }
}
