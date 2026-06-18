import AVFoundation
import Accelerate

/// Taps audio and feeds a normalized 128-band spectrum to wallpapers via
/// `livelyAudioListener` (web) and the shader `audio` uniform (Metal). Off by default;
/// sleeps when silent. Uses the input device (ambient/system audio); needs mic permission.
@MainActor
final class AudioFeeder {
    private let manager: WallpaperWindowManager
    private let engine = AVAudioEngine()
    private var running = false
    private let fft = FFTProcessor(size: 1024)
    private var silentTicks = 0

    init(manager: WallpaperWindowManager) {
        self.manager = manager
    }

    var isEnabled = false {
        didSet { isEnabled ? start() : stop() }
    }

    private func start() {
        guard !running else { return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor in if granted { self?.begin() } }
        }
    }

    private func begin() {
        guard !running else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let bands = self?.fft.process(channel, count: Int(buffer.frameLength)) ?? []
            Task { @MainActor in self?.deliver(bands) }
        }
        engine.prepare()
        do { try engine.start(); running = true }
        catch { NSLog("[LucidWallpaper] audio engine failed: %@", "\(error)") }
    }

    private func deliver(_ bands: [Float]) {
        guard !bands.isEmpty else { return }
        // Auto-sleep delivery when silent to avoid waking GPUs needlessly.
        let energy = bands.reduce(0, +) / Float(bands.count)
        if energy < 0.002 {
            silentTicks += 1
            if silentTicks > 30 { return }
        } else {
            silentTicks = 0
        }
        manager.sendAudio(bands)
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }
}

/// Real FFT → 128 normalized magnitude bands.
private final class FFTProcessor {
    private let n: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup?
    private var window: [Float]
    private let bandCount = 128

    init(size: Int) {
        n = size
        log2n = vDSP_Length(log2(Float(size)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
    }

    deinit { if let setup { vDSP_destroy_fftsetup(setup) } }

    func process(_ samples: UnsafePointer<Float>, count: Int) -> [Float] {
        guard let setup, count >= n else { return [] }
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(n))

        var real = [Float](repeating: 0, count: n / 2)
        var imag = [Float](repeating: 0, count: n / 2)
        var magnitudes = [Float](repeating: 0, count: n / 2)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { wptr in
                    wptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { typed in
                        vDSP_ctoz(typed, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(n / 2))
            }
        }

        // Group n/2 bins into 128 bands, log-scale + normalize.
        let bins = n / 2
        let perBand = max(1, bins / bandCount)
        var bands = [Float](repeating: 0, count: bandCount)
        for b in 0..<bandCount {
            let start = b * perBand
            let end = min(bins, start + perBand)
            guard start < end else { break }
            var sum: Float = 0
            for i in start..<end { sum += magnitudes[i] }
            let avg = sum / Float(end - start)
            bands[b] = min(1.0, log10(1 + avg) * 0.25)
        }
        return bands
    }
}
