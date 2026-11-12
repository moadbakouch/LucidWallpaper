import AppKit
import WebKit
import Darwin
import QuartzCore

/// Self-contained telemetry feeder for the screensaver's web wallpapers. The screensaver is a
/// separate bundle that doesn't link the main app's `Sources`, so this mirrors the app's
/// SystemFeeders / EnvironmentFeeder using the same Lively JS bridge names
/// (`livelySystemInformation`, `livelyCurrentTrack`, `livelyEnvironment` / `lucidEnvironment`),
/// so a wallpaper reacts identically whether it runs on the desktop or as the screensaver.
@MainActor
final class SaverFeeds {
    private weak var webView: WKWebView?
    private var timer: Timer?
    private var tick = 0

    // CPU / network deltas between samples.
    private var prevCPU: host_cpu_load_info?
    private var prevNet: (rx: UInt64, tx: UInt64, time: CFTimeInterval)?

    // Cached weather, refreshed roughly every 15 minutes (best effort; no key, no permission).
    private var weather: [String: Any] = ["available": false]
    private var location: [String: Any] = [:]
    private var lastWeatherFetch = 0.0

    init(webView: WKWebView) {
        self.webView = webView
    }

    func start() {
        guard timer == nil else { return }
        pushEnvironment()   // time / theme immediately so the page starts correct
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onTick() }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate(); timer = nil
    }

    private func onTick() {
        guard webView != nil else { return }
        sendSystemInfo()
        sendNowPlaying()
        tick += 1
        if tick % 5 == 0 { pushEnvironment() }   // ~5 s cadence for time/theme/weather
    }

    // MARK: JS bridge

    private func evaluate(_ js: String) {
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: System info

    private func sendSystemInfo() {
        let net = networkBytesPerSec()
        let json = """
        {"CurrentCpu":\(round2(cpuPercent())),"CurrentRam":\(round2(ramPercent())),\
        "RamUsageMB":\(ramUsedMB()),"CurrentGpu":0,\
        "NetDownSpeed":\(net.down),"NetUpSpeed":\(net.up)}
        """
        evaluate("if(window.livelySystemInformation){window.livelySystemInformation(\(json));}")
    }

    private func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    private func cpuPercent() -> Double {
        guard let load = hostCPULoad() else { return 0 }
        defer { prevCPU = load }
        guard let prev = prevCPU else { return 0 }
        let user = Double(load.cpu_ticks.0 - prev.cpu_ticks.0)
        let system = Double(load.cpu_ticks.1 - prev.cpu_ticks.1)
        let idle = Double(load.cpu_ticks.2 - prev.cpu_ticks.2)
        let nice = Double(load.cpu_ticks.3 - prev.cpu_ticks.3)
        let total = user + system + idle + nice
        return total > 0 ? (user + system + nice) / total * 100 : 0
    }

    private func hostCPULoad() -> host_cpu_load_info? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    private func vmStats() -> vm_statistics64? {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        var info = vm_statistics64()
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    private func ramUsedBytes() -> UInt64 {
        guard let vm = vmStats() else { return 0 }
        let page = UInt64(vm_kernel_page_size)
        return (UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * page
    }

    private func ramUsedMB() -> Int { Int(ramUsedBytes() / 1_048_576) }
    private func ramPercent() -> Double {
        let total = ProcessInfo.processInfo.physicalMemory
        return total > 0 ? Double(ramUsedBytes()) / Double(total) * 100 : 0
    }

    private func networkBytesPerSec() -> (down: UInt64, up: UInt64) {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            if let addr = cur.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               let data = cur.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                let name = String(cString: cur.pointee.ifa_name)
                if name.hasPrefix("en") || name.hasPrefix("pdp") {
                    rx += UInt64(data.pointee.ifi_ibytes)
                    tx += UInt64(data.pointee.ifi_obytes)
                }
            }
            ptr = cur.pointee.ifa_next
        }
        let now = CACurrentMediaTime()
        defer { prevNet = (rx, tx, now) }
        guard let prev = prevNet, now > prev.time else { return (0, 0) }
        let dt = now - prev.time
        let down = rx >= prev.rx ? UInt64(Double(rx - prev.rx) / dt) : 0
        let up = tx >= prev.tx ? UInt64(Double(tx - prev.tx) / dt) : 0
        return (down, up)
    }

    // MARK: Now-playing (private MediaRemote framework, best effort)

    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private static let getNowPlaying: GetInfoFn? = {
        guard let bundle = CFBundleCreate(kCFAllocatorDefault,
                URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework") as CFURL),
              let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString)
        else { return nil }
        return unsafeBitCast(ptr, to: GetInfoFn.self)
    }()

    private func sendNowPlaying() {
        guard let getInfo = Self.getNowPlaying else { return }
        getInfo(DispatchQueue.main) { [weak self] info in
            let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
            let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            let album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
            if title.isEmpty && artist.isEmpty { return }
            var thumb = ""
            if let art = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                thumb = "data:image/png;base64," + art.base64EncodedString()
            }
            let dict: [String: Any] = ["title": title, "artist": artist, "album": album, "thumbnail": thumb]
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let json = String(data: data, encoding: .utf8) else { return }
            self?.evaluate("if(window.livelyCurrentTrack){window.livelyCurrentTrack(\(json));}")
        }
    }

    // MARK: Environment (time / theme / weather)

    private func pushEnvironment() {
        let now = Date().timeIntervalSince1970
        if weatherStale(now) { fetchWeather() }
        let payload: [String: Any] = [
            "time": timePayload(),
            "theme": themePayload(),
            "weather": weather,
            "location": location,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        evaluate("window.lucidEnvironment=\(json);if(window.livelyEnvironment){window.livelyEnvironment(\(json));}")
    }

    private func weatherStale(_ now: Double) -> Bool {
        let have = (weather["available"] as? Bool) == true
        return now - lastWeatherFetch > (have ? 900 : 180)
    }

    private func timePayload() -> [String: Any] {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
        let h = c.hour ?? 0, m = c.minute ?? 0, s = c.second ?? 0
        let frac = (Double(h) * 3600 + Double(m) * 60 + Double(s)) / 86400.0
        var isNight = h < 6 || h >= 20
        if let isDay = (weather["isDay"] as? Bool) { isNight = !isDay }
        return ["hour": h, "minute": m, "dayFraction": frac, "isNight": isNight]
    }

    private func themePayload() -> [String: Any] {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor.systemBlue.usingColorSpace(.sRGB)
        let hex: String
        if let accent {
            hex = String(format: "#%02X%02X%02X",
                         Int(round(accent.redComponent * 255)),
                         Int(round(accent.greenComponent * 255)),
                         Int(round(accent.blueComponent * 255)))
        } else {
            hex = "#0A84FF"
        }
        return ["isDark": dark, "accent": hex]
    }

    private func fetchWeather() {
        lastWeatherFetch = Date().timeIntervalSince1970
        Task { [weak self] in
            guard let coord = await Self.fetchLocation(),
                  let w = await Self.fetchOpenMeteo(lat: coord.lat, lon: coord.lon) else { return }
            await MainActor.run {
                self?.location = ["city": coord.city, "lat": coord.lat, "lon": coord.lon]
                self?.weather = w
                self?.pushEnvironment()
            }
        }
    }

    private static func fetchLocation() async -> (lat: Double, lon: Double, city: String)? {
        guard let url = URL(string: "https://ipapi.co/json/"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lat = obj["latitude"] as? Double, let lon = obj["longitude"] as? Double else { return nil }
        return (lat, lon, (obj["city"] as? String) ?? "")
    }

    private static func fetchOpenMeteo(lat: Double, lon: Double) async -> [String: Any]? {
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)" +
            "&current=temperature_2m,weather_code,cloud_cover,wind_speed_10m,is_day&timezone=auto"
        guard let url = URL(string: urlStr),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = obj["current"] as? [String: Any] else { return nil }
        let code = (cur["weather_code"] as? Int) ?? (cur["weather_code"] as? Double).map(Int.init) ?? 0
        let isDay = ((cur["is_day"] as? Int) ?? 1) == 1
        return [
            "available": true,
            "code": code,
            "temperature": cur["temperature_2m"] ?? 0,
            "cloud": cur["cloud_cover"] ?? 0,
            "wind": cur["wind_speed_10m"] ?? 0,
            "isDay": isDay,
            "isRaining": (51...67).contains(code) || (80...82).contains(code) || (95...99).contains(code),
            "isSnowing": (71...77).contains(code) || (85...86).contains(code),
            "description": describe(code),
        ]
    }

    private static func describe(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1, 2, 3: return "Partly cloudy"
        case 45, 48: return "Fog"
        case 51...57: return "Drizzle"
        case 61...67: return "Rain"
        case 71...77: return "Snow"
        case 80...82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95...99: return "Thunderstorm"
        default: return "-"
        }
    }
}
