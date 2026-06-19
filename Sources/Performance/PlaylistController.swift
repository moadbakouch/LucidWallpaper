import Foundation

/// Auto-rotates the wallpaper with crossfades. If a playlist is set, it cycles through that
/// (honoring each entry's duration); otherwise it rotates the whole library on a fixed
/// interval. Sequential or shuffle. Off by default.
@MainActor
final class PlaylistController {
    private let model: AppModel
    private var timer: Timer?
    private var index = 0
    private var epoch = 0   // bumped on (re)schedule/stop so a late timer fire is ignored

    var isEnabled = false { didSet { reschedule() } }
    var intervalSeconds: TimeInterval = 600 { didSet { reschedule() } }
    var shuffle = false
    /// The ordered playlist (empty = rotate the whole library).
    var entries: [PlaylistEntry] = [] { didSet { reschedule() } }

    init(model: AppModel) {
        self.model = model
    }

    func reschedule() {
        timer?.invalidate(); timer = nil
        guard isEnabled else { return }
        if entries.isEmpty {
            guard intervalSeconds > 0 else { return }
            schedule(after: intervalSeconds, repeats: true) { [weak self] in self?.advanceLibrary() }
        } else {
            index = min(index, entries.count - 1)
            scheduleNextPlaylistStep()
        }
    }

    func stop() {
        epoch += 1
        timer?.invalidate(); timer = nil
    }

    // MARK: Library rotation (no playlist)

    private func advanceLibrary() {
        guard model.items.count > 1 else { return }
        model.suppressingPerSpaceRecording {
            shuffle ? model.randomWallpaper(crossfade: true) : model.cycleWallpaper(by: 1, crossfade: true)
        }
    }

    // MARK: Playlist rotation

    private func scheduleNextPlaylistStep() {
        guard isEnabled, !entries.isEmpty else { return }
        let secs = TimeInterval(max(1, entries[index % entries.count].seconds))
        schedule(after: secs, repeats: false) { [weak self] in self?.advancePlaylist() }
    }

    private func advancePlaylist() {
        guard !entries.isEmpty else { return }
        if shuffle { index = Int.random(in: 0..<entries.count) }
        else { index = (index + 1) % entries.count }
        if let item = model.items.first(where: { $0.id == entries[index].itemID }) {
            model.suppressingPerSpaceRecording { model.apply(item, addToLibrary: false, crossfade: true) }
        }
        scheduleNextPlaylistStep()
    }

    private func schedule(after seconds: TimeInterval, repeats: Bool, _ action: @escaping () -> Void) {
        epoch += 1
        let myEpoch = epoch
        let t = Timer(timeInterval: seconds, repeats: repeats) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.epoch == myEpoch else { return }   // ignore a fire from a stale timer
                action()
            }
        }
        t.tolerance = min(5, seconds * 0.1)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
