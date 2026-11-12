import AVFoundation
import CoreAudio

/// Plays an optional looping ambient sound tied to the current wallpaper. Muted by default
/// (master volume 0). Pauses with the wallpaper. Play/stop is owned by `setSound` +
/// `suspend`/`resume` (driven by AppModel.updateAudio); `volume` only sets the live level.
///
/// When ducking is enabled, the ambient sound automatically drops to a fraction of its level
/// while *another* app is outputting audio (Spotify, a video call, a YouTube tab) and ramps
/// back up when that audio stops - so wallpaper ambience never competes with real audio.
@MainActor
final class AudioController {
    private var player: AVAudioPlayer?
    private var currentURL: URL?
    private var suspended = false
    private let ducker = OtherAudioMonitor()

    /// Master level (0...1). Setting it re-applies the effective (possibly ducked) volume.
    var volume: Float = 0 {
        didSet {
            applyVolume(fade: 0)
            updateDuckMonitor()   // crossing 0 (mute/unmute) changes whether we should listen
        }
    }

    /// Duck the ambient sound while another app plays audio (user setting).
    var duckingEnabled = false {
        didSet {
            guard duckingEnabled != oldValue else { return }
            updateDuckMonitor()
            applyVolume(fade: 0.3)
        }
    }

    /// Whether another app is currently outputting audio (driven by the monitor).
    private var isDucked = false

    /// How far to drop the ambient sound while other audio is playing.
    private static let duckFactor: Float = 0.15

    init() {
        ducker.onChange = { [weak self] otherAudioActive in
            guard let self else { return }
            self.isDucked = otherAudioActive
            self.applyVolume(fade: 0.4)
        }
    }

    /// The level actually fed to the player: ducked while another app plays audio.
    private var effectiveVolume: Float {
        (duckingEnabled && isDucked) ? volume * Self.duckFactor : volume
    }

    private func applyVolume(fade: TimeInterval) {
        guard let player else { return }
        if fade > 0 { player.setVolume(effectiveVolume, fadeDuration: fade) }
        else { player.volume = effectiveVolume }
    }

    /// Set the sound for the active wallpaper (nil = silence). AppModel only passes a URL
    /// when audio should actually play (volume > 0); it re-calls this after volume changes.
    func setSound(_ url: URL?) {
        guard url != currentURL else { return }
        currentURL = url
        player?.stop(); player = nil
        guard let url, volume > 0 else { updateDuckMonitor(); return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.volume = effectiveVolume
        if !suspended { player?.play() }
        updateDuckMonitor()
    }

    func suspend() { suspended = true; player?.pause(); updateDuckMonitor() }
    func resume() { suspended = false; if volume > 0 { player?.play() }; updateDuckMonitor() }
    func stop() {
        player?.stop(); player = nil; currentURL = nil; suspended = false
        ducker.stop(); isDucked = false
    }

    /// Whether the ambient sound is actually audible right now (a loaded, unsuspended, audible
    /// player) - the only time it's worth watching for other audio to duck against.
    private var isActivelyPlaying: Bool { player != nil && !suspended && volume > 0 }

    /// Run the other-audio monitor only when ducking is on and the sound is actually playing.
    /// When we stop watching, undo any active duck so the level isn't left attenuated.
    private func updateDuckMonitor() {
        if duckingEnabled && isActivelyPlaying {
            ducker.start()
        } else {
            ducker.stop()
            if isDucked { isDucked = false; applyVolume(fade: 0.2) }
        }
    }

    /// Debug: whether a sound is actively playing; used by the feature test.
    var debugIsPlaying: Bool { player?.isPlaying ?? false }
    /// Debug: whether the ambient sound is currently ducked for other audio.
    var debugIsDucked: Bool { duckingEnabled && isDucked }
}

/// Watches whether any process *other than us* is currently outputting audio, using CoreAudio's
/// per-process audio objects (macOS 14.4+). Polling (every ~1.5 s) is cheap and avoids the
/// self-trigger problem of `kAudioDevicePropertyDeviceIsRunningSomewhere`, which would be true
/// merely because our own ambient player is running. On older systems it reports "no other
/// audio" (ducking simply does nothing).
@MainActor
final class OtherAudioMonitor {
    var onChange: ((Bool) -> Void)?
    private var timer: Timer?
    private let myPID = ProcessInfo.processInfo.processIdentifier
    private(set) var otherAudioActive = false

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll()   // immediate (after timer is set), so a duck takes effect on the first frame
    }

    func stop() {
        timer?.invalidate(); timer = nil
        otherAudioActive = false
    }

    private func poll() {
        // A poll Task may already be queued when stop() runs; ignore it so we never re-duck after
        // the monitor was told to stop (which would strand the ambient sound at the ducked level).
        guard timer != nil else { return }
        let active = Self.isOtherAudioPlaying(excluding: myPID)
        guard active != otherAudioActive else { return }
        otherAudioActive = active
        onChange?(active)
    }

    /// True if any audio process other than `myPID` is currently running output.
    static func isOtherAudioPlaying(excluding myPID: pid_t) -> Bool {
        guard #available(macOS 14.4, *) else { return false }

        let system = AudioObjectID(kAudioObjectSystemObject)
        var listAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &listAddress, 0, nil, &dataSize) == noErr else { return false }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return false }

        var processes = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &listAddress, 0, nil, &dataSize, &processes) == noErr else { return false }

        for proc in processes {
            // Skip our own process so the ambient player never ducks itself.
            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var pid: pid_t = -1
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            if AudioObjectGetPropertyData(proc, &pidAddress, 0, nil, &pidSize, &pid) == noErr, pid == myPID {
                continue
            }

            var runAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningOutput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0
            var runSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(proc, &runAddress, 0, nil, &runSize, &running) == noErr, running != 0 {
                return true
            }
        }
        return false
    }
}
