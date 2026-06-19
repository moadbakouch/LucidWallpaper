import AVFoundation

/// Plays an optional looping ambient sound tied to the current wallpaper. Muted by default
/// (master volume 0). Pauses with the wallpaper. Play/stop is owned by `setSound` +
/// `suspend`/`resume` (driven by AppModel.updateAudio); `volume` only sets the live level.
@MainActor
final class AudioController {
    private var player: AVAudioPlayer?
    private var currentURL: URL?
    private var suspended = false

    var volume: Float = 0 { didSet { player?.volume = volume } }

    /// Set the sound for the active wallpaper (nil = silence). AppModel only passes a URL
    /// when audio should actually play (volume > 0); it re-calls this after volume changes.
    func setSound(_ url: URL?) {
        guard url != currentURL else { return }
        currentURL = url
        player?.stop(); player = nil
        guard let url, volume > 0 else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.volume = volume
        if !suspended { player?.play() }
    }

    func suspend() { suspended = true; player?.pause() }
    func resume() { suspended = false; if volume > 0 { player?.play() } }
    func stop() { player?.stop(); player = nil; currentURL = nil; suspended = false }
}
