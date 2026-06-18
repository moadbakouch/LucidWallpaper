import Foundation
import Darwin
import QuartzCore

/// Pushes CPU / RAM / network stats to web wallpapers via `livelySystemInformation`,
/// and now-playing metadata via `livelyCurrentTrack`. Runs only while a web wallpaper
/// is active. Best-effort: GPU% has no public API; now-playing uses MediaRemote.
@MainActor
final class SystemFeeders {
    private let manager: WallpaperWindowManager
    private var timer: Timer?

    var systemInfoEnabled = true
    var nowPlayingEnabled = true

    private var prevCPU: host_cpu_load_info?
    private var prevNet: (rx: UInt64, tx: UInt64, time: CFTimeInterval)?

    init(manager: WallpaperWindowManager) {
        self.manager = manager
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard manager.hasWebRenderer else { return }
        if systemInfoEnabled {
            let net = networkBytesPerSec()
            let json = """
            {"CurrentCpu":\(round2(cpuPercent())),"CurrentRam":\(round2(ramPercent())),\
            "RamUsageMB":\(ramUsedMB()),"CurrentGpu":0,\
            "NetDownSpeed":\(net.down),"NetUpSpeed":\(net.up)}
            """
            manager.sendSystemInfo(json)
        }
        if nowPlayingEnabled {
            NowPlaying.fetch { [weak self] json in
                guard let json else { return }
                self?.manager.sendNowPlaying(json)
            }
        }
    }

    private func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    // MARK: CPU

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

    // MARK: RAM

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

    // MARK: Network

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
}

/// Now-playing metadata via the private MediaRemote framework (best-effort).
enum NowPlaying {
    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private static let getInfo: GetInfoFn? = {
        guard let bundle = CFBundleCreate(kCFAllocatorDefault,
                URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework") as CFURL),
              let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString)
        else { return nil }
        return unsafeBitCast(ptr, to: GetInfoFn.self)
    }()

    static func fetch(_ completion: @escaping (String?) -> Void) {
        guard let getInfo else { completion(nil); return }
        getInfo(DispatchQueue.main) { info in
            let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
            let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            let album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
            if title.isEmpty && artist.isEmpty { completion(nil); return }
            var thumb = ""
            if let art = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                thumb = "data:image/png;base64," + art.base64EncodedString()
            }
            let dict: [String: Any] = ["title": title, "artist": artist, "album": album, "thumbnail": thumb]
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let json = String(data: data, encoding: .utf8) {
                completion(json)
            } else {
                completion(nil)
            }
        }
    }
}
