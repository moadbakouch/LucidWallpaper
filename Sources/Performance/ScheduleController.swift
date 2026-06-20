import AppKit

/// Switches between a "day" and "night" wallpaper based on the system appearance
/// (Light/Dark) or the time of day. (Focus-mode switching has no public macOS API.)
@MainActor
final class ScheduleController {
    enum Mode: String { case off, appearance, time }

    private let model: AppModel
    private var appearanceObserver: NSKeyValueObservation?
    private var timer: Timer?

    var mode: Mode = .off
    var dayItemID: UUID?
    var nightItemID: UUID?
    var nightStartHour = 19   // 7pm
    var dayStartHour = 7      // 7am

    init(model: AppModel) {
        self.model = model
    }

    func reconfigure() {
        appearanceObserver = nil
        timer?.invalidate()
        timer = nil

        switch mode {
        case .off:
            break
        case .appearance:
            appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
                Task { @MainActor in self?.applyForAppearance() }
            }
            applyForAppearance()
        case .time:
            // Add in .common mode so the day/night check keeps firing while a menu/modal tracking
            // loop is active (Timer.scheduledTimer uses .default only, and would stall).
            let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.applyForTime() }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            applyForTime()
        }
    }

    func stop() {
        appearanceObserver = nil
        timer?.invalidate()
        timer = nil
    }

    private func systemIsDark() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func applyForAppearance() {
        applyItem(systemIsDark() ? nightItemID : dayItemID)
    }

    private func applyForTime() {
        let hour = Calendar.current.component(.hour, from: Date())
        let isNight = hour >= nightStartHour || hour < dayStartHour
        applyItem(isNight ? nightItemID : dayItemID)
    }

    private func applyItem(_ id: UUID?) {
        guard let id,
              model.currentItemID != id,
              let item = model.library.items.first(where: { $0.id == id }) else { return }
        model.suppressingPerSpaceRecording { model.apply(item, addToLibrary: false, crossfade: true) }
    }
}
