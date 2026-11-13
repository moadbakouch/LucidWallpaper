import AVFoundation

/// Short interface chimes for the first-run setup (welcome / step / select / done).
///
/// Everything is synthesized at runtime - a handful of bell-like partials through a tiny reverb -
/// and played from in-memory WAV data, so there's no audio asset to bundle or license. Gated by
/// the "Interface sounds" preference (default on).
@MainActor
enum SoundEffects {
    enum Effect: CaseIterable { case welcome, step, select, done }

    private static let defaultsKey = "interfaceSoundsEnabled"

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: defaultsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: defaultsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    private static var players: [Effect: AVAudioPlayer] = [:]

    /// Render every effect up front so the first `play` doesn't hitch an animation.
    static func prepare() {
        for effect in Effect.allCases where players[effect] == nil {
            guard let player = try? AVAudioPlayer(data: Synth.wav(for: effect)) else { continue }
            player.prepareToPlay()
            players[effect] = player
        }
    }

    static func play(_ effect: Effect, volume: Float = 0.55) {
        guard isEnabled else { return }
        prepare()
        guard let player = players[effect] else { return }
        player.volume = volume
        player.currentTime = 0
        player.play()
    }
}

/// Additive bell/pad synthesis → 16-bit stereo WAV.
private enum Synth {
    static let sampleRate = 44_100.0

    struct Note {
        var freq: Double
        var start: Double
        var duration: Double
        var gain: Double
        var attack: Double = 0.006
        var pan: Double = 0          // -1 (left) … 1 (right)
    }

    static func wav(for effect: SoundEffects.Effect) -> Data {
        switch effect {
        case .welcome:
            // A soft A-major pad swelling under a rising, shimmering arpeggio.
            var notes = [
                Note(freq: 110.00, start: 0, duration: 3.4, gain: 0.20, attack: 0.5),
                Note(freq: 220.00, start: 0, duration: 3.4, gain: 0.22, attack: 0.45, pan: -0.3),
                Note(freq: 329.63, start: 0.05, duration: 3.2, gain: 0.16, attack: 0.5, pan: 0.3),
            ]
            let arp: [Double] = [440.00, 554.37, 659.25, 880.00, 1108.73, 1318.51]
            for (i, f) in arp.enumerated() {
                notes.append(Note(freq: f, start: 0.18 + Double(i) * 0.105, duration: 2.2,
                                  gain: 0.30 - Double(i) * 0.03, pan: i % 2 == 0 ? -0.45 : 0.45))
            }
            notes.append(Note(freq: 1760.00, start: 0.95, duration: 2.4, gain: 0.10, attack: 0.02))
            return render(notes, length: 4.0, reverb: 0.34)
        case .done:
            return render([
                Note(freq: 220.00, start: 0, duration: 1.6, gain: 0.20, attack: 0.03),
                Note(freq: 659.25, start: 0, duration: 1.3, gain: 0.30, pan: -0.3),
                Note(freq: 880.00, start: 0.085, duration: 1.4, gain: 0.30, pan: 0.3),
                Note(freq: 1318.51, start: 0.17, duration: 1.7, gain: 0.26),
            ], length: 2.2, reverb: 0.3)
        case .step:
            return render([Note(freq: 880.00, start: 0, duration: 0.22, gain: 0.30),
                           Note(freq: 1318.51, start: 0.03, duration: 0.22, gain: 0.16)],
                          length: 0.5, reverb: 0.16)
        case .select:
            return render([Note(freq: 659.25, start: 0, duration: 0.2, gain: 0.32),
                           Note(freq: 987.77, start: 0.045, duration: 0.26, gain: 0.22)],
                          length: 0.55, reverb: 0.18)
        }
    }

    private static func render(_ notes: [Note], length: Double, reverb: Double) -> Data {
        let count = Int(length * sampleRate)
        var left = [Double](repeating: 0, count: count)
        var right = [Double](repeating: 0, count: count)

        for note in notes {
            let first = Int(note.start * sampleRate)
            let n = min(Int(note.duration * sampleRate), count - first)
            guard n > 0 else { continue }
            let decay = 5.0 / note.duration            // ≈ -43 dB by the end of the note
            let w = 2 * Double.pi * note.freq / sampleRate
            let lGain = note.gain * (1 - max(0, note.pan)) , rGain = note.gain * (1 + min(0, note.pan))
            for i in 0..<n {
                let t = Double(i) / sampleRate
                let env = min(1, t / note.attack) * exp(-decay * t)
                let phase = w * Double(i)
                // Fundamental + two soft overtones (the second slightly sharp, like a bell).
                let s = env * (sin(phase) + 0.28 * sin(2 * phase) * exp(-2 * t) + 0.09 * sin(3.01 * phase) * exp(-4 * t))
                left[first + i] += s * lGain
                right[first + i] += s * rGain
            }
        }

        if reverb > 0 {
            left = reverberate(left, delays: [0.0297, 0.0371, 0.0411, 0.0437], mix: reverb)
            right = reverberate(right, delays: [0.0307, 0.0359, 0.0423, 0.0449], mix: reverb)
        }

        // Normalize, then a short fade-out so the tail never clicks.
        let peak = max(left.map { abs($0) }.max() ?? 1, right.map { abs($0) }.max() ?? 1, 0.0001)
        let scale = 0.82 / peak
        let fade = min(count, Int(0.08 * sampleRate))
        var pcm = Data(capacity: count * 4)
        for i in 0..<count {
            let tail = i >= count - fade ? Double(count - i) / Double(fade) : 1
            for sample in [left[i], right[i]] {
                let v = Int16(max(-1, min(1, sample * scale * tail)) * Double(Int16.max))
                withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
            }
        }
        return header(dataBytes: pcm.count) + pcm
    }

    /// Four parallel feedback combs - enough to give the chime a little air.
    private static func reverberate(_ input: [Double], delays: [Double], mix: Double) -> [Double] {
        var wet = [Double](repeating: 0, count: input.count)
        for delay in delays {
            let d = Int(delay * sampleRate)
            var buffer = [Double](repeating: 0, count: input.count)
            for i in 0..<input.count {
                let fed = i >= d ? buffer[i - d] * 0.78 : 0
                buffer[i] = input[i] + fed
                wet[i] += fed
            }
        }
        let wetGain = mix / Double(delays.count)
        return zip(input, wet).map { $0 + $1 * wetGain }
    }

    private static func header(dataBytes: Int) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let rate = UInt32(sampleRate)
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + dataBytes))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(2)
        u32(rate); u32(rate * 4); u16(4); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(dataBytes))
        return d
    }
}
