import AppKit

/// The "Send Feedback" destination.
///
/// ┌──────────────────────────────────────────────────────────────────────────────┐
/// │  TO LINK YOUR OWN FEEDBACK CHANNEL: set `link` below to your URL.               │
/// │    Google Form:   URL(string: "https://forms.gle/XXXXXXXX")                     │
/// │    Typeform:      URL(string: "https://yourname.typeform.com/to/XXXX")          │
/// │    GitHub issues: URL(string: "https://github.com/you/repo/issues/new")         │
/// │    Discord:       URL(string: "https://discord.gg/XXXX")                        │
/// │    Email:         URL(string: "mailto:you@example.com")                         │
/// │  Or leave it nil to use the built-in email draft (prefilled with the app +      │
/// │  macOS version), addressed to `contactEmail`.                                   │
/// └──────────────────────────────────────────────────────────────────────────────┘
enum Feedback {
    /// >>> EDIT ME <<<  Your feedback link, or `nil` to use the email draft below.
    static let link: URL? = nil

    /// Used only when `link` is nil. Replace with the address you want feedback sent to.
    static let contactEmail = "feedback@example.com"

    /// Where the Send Feedback action actually goes.
    static var destination: URL { link ?? mailtoDraft }

    /// Open the feedback destination in the default browser / mail client.
    static func submit() { NSWorkspace.shared.open(destination) }

    /// App + macOS version line, appended to the email draft (and handy to show in-app).
    static var versionLine: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "LucidWallpaper \(v) (\(b)) - macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }

    // MARK: Email-draft fallback

    private static var mailtoDraft: URL {
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = contactEmail
        comps.queryItems = [
            URLQueryItem(name: "subject", value: "LucidWallpaper Feedback"),
            URLQueryItem(name: "body", value: "\n\n---\n\(versionLine)"),
        ]
        return comps.url ?? URL(string: "mailto:\(contactEmail)")!
    }
}
