import AppKit

// Unbuffer stderr so diagnostic NSLog output appears live when redirected to a file (the test
// harnesses grep it). Buffered stderr is otherwise flushed only on a clean exit, so markers were
// lost when a harness `killall`-ed the app mid-run.
setvbuf(stderr, nil, _IONBF, 0)

// Lucid Wallpaper is a menu-bar agent. We drive the AppKit lifecycle directly (no storyboard,
// no @main App) so we have full control over window levels and activation policy.
// The process entry point is the main thread, so we assert main-actor isolation to set up
// our @MainActor-isolated controllers. app.run() blocks here until termination, keeping
// `delegate` alive (NSApplication.delegate is a weak reference).
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate

    // .accessory == agent app with no Dock icon (mirrors LSUIElement in Info.plist).
    app.setActivationPolicy(.accessory)
    app.run()
}
