import AppKit

/// Pushes ambient context to web wallpapers via `window.livelyEnvironment(json)` (and
/// `window.lucidEnvironment`): time of day, the system theme (accent + light/dark), and best-
/// effort local weather (IP geolocation + Open-Meteo - no location permission, no API key).
/// Only runs while a web wallpaper is loaded.
@MainActor
final class EnvironmentFeeder {
    private let manager: WallpaperWindowManager
    private var timer: Timer?
    private var started = false
    private var appearanceObservation: NSKeyValueObservation?

    /// Cached weather, refreshed roughly every 15 minutes.
    private var weather: [String: Any] = ["available": false]
    private var location: [String: Any] = [:]
    private var lastWeatherFetch = 0.0

    var enabled = true { didSet { refresh() } }
    var contentHasWeb = false { didSet { refresh() } }

    init(manager: WallpaperWindowManager) {
        self.manager = manager
    }

    func start() {
        started = true
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.push() }
        }
        refresh()
    }

    func stop() {
        started = false
        appearanceObservation = nil
        timer?.invalidate(); timer = nil
    }

    private func refresh() {
        let run = started && enabled && contentHasWeb
        if run {
            guard timer == nil else { return }
            push()   // immediate
            let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.onTimer() }
            }
            t.tolerance = 5
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else {
            timer?.invalidate(); timer = nil
        }
    }

    private func onTimer() { push() }

    // MARK: Payload

    private func push() {
        // Refresh weather at most every ~15 minutes.
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
        manager.sendEnvironment(json)
    }

    private func weatherStale(_ now: Double) -> Bool {
        // Refresh good weather every ~15 min; back off a failed/missing fetch to ~3 min
        // (lastWeatherFetch is stamped up-front, so a failure won't refetch every tick).
        let have = (weather["available"] as? Bool) == true
        return now - lastWeatherFetch > (have ? 900 : 180)
    }

    private func timePayload() -> [String: Any] {
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute, .second], from: Date())
        let h = c.hour ?? 0, m = c.minute ?? 0, s = c.second ?? 0
        let frac = (Double(h) * 3600 + Double(m) * 60 + Double(s)) / 86400.0
        // Night = before sunrise or after sunset when known; else a simple 6–20 window.
        var isNight = h < 6 || h >= 20
        if let isDay = (weather["isDay"] as? Bool) { isNight = !isDay }
        return ["hour": h, "minute": m, "dayFraction": frac, "isNight": isNight]
    }

    private func themePayload() -> [String: Any] {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Must convert to an RGB colorspace before reading components - reading red/green/blue
        // on a catalog/named color (e.g. a non-converted systemBlue) raises an NSException.
        let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB)
            ?? NSColor.systemBlue.usingColorSpace(.sRGB)
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

    // MARK: Weather (best effort, no key)

    private func fetchWeather() {
        lastWeatherFetch = Date().timeIntervalSince1970
        Task { [weak self] in
            guard let coord = await Self.fetchLocation() else { return }
            guard let w = await Self.fetchOpenMeteo(lat: coord.lat, lon: coord.lon) else { return }
            await MainActor.run {
                self?.location = ["city": coord.city, "lat": coord.lat, "lon": coord.lon]
                self?.weather = w
                self?.push()
            }
        }
    }

    static func fetchLocation() async -> (lat: Double, lon: Double, city: String)? {
        guard let url = URL(string: "https://ipapi.co/json/") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lat = obj["latitude"] as? Double, let lon = obj["longitude"] as? Double else { return nil }
        return (lat, lon, (obj["city"] as? String) ?? "")
    }

    static func fetchOpenMeteo(lat: Double, lon: Double) async -> [String: Any]? {
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
