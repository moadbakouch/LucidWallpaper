import AppKit

/// In-app feedback. Each report is POSTed to a Google Apps Script web app (running as you)
/// which saves it as its own file inside a Drive folder called "Wallpaper Issues".
///
/// ┌──────────────────────────────────────────────────────────────────────────────┐
/// │  SETUP (about 2 minutes) - see scripts/feedback-appsscript.gs:                 │
/// │   1. script.google.com → New project → paste that script → Deploy as Web app   │
/// │      (Execute as: Me, Who has access: Anyone).                                  │
/// │   2. Copy the /exec URL it gives you.                                           │
/// │   3. Paste it into `configuredEndpoint` below.                                  │
/// │  Until then, the form falls back to opening an email draft to `contactEmail`.   │
/// └──────────────────────────────────────────────────────────────────────────────┘
enum Feedback {
    /// >>> EDIT ME <<<  Your Apps Script web-app URL, or nil to use the email fallback.
    static let configuredEndpoint: URL? = nil   // e.g. URL(string: "https://script.google.com/macros/s/AKfy.../exec")

    /// Used only when there's no endpoint (the email-draft fallback).
    static let contactEmail = "feedback@example.com"

    /// Effective endpoint (an env override lets the build be tested without editing the constant).
    static var endpoint: URL? {
        if let s = ProcessInfo.processInfo.environment["LUCIDWALL_FEEDBACK_ENDPOINT"], let u = URL(string: s) { return u }
        return configuredEndpoint
    }

    struct Report {
        var category: String
        var message: String
        var email: String
        var wallpaper: String
        var appVersion: String
        var system: String
    }

    enum Outcome: Equatable { case sent, openedMail, failed(String) }

    static func makeReport(category: String, message: String, email: String, wallpaper: String) -> Report {
        Report(category: category, message: message, email: email, wallpaper: wallpaper,
               appVersion: appVersion, system: ProcessInfo.processInfo.operatingSystemVersionString)
    }

    /// Send a report. POSTs JSON to the endpoint if configured; otherwise opens an email draft.
    static func send(_ report: Report) async -> Outcome {
        guard let endpoint else { openMail(report); return .openedMail }
        do {
            var req = URLRequest(url: endpoint, timeoutInterval: 25)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "category": report.category, "message": report.message, "email": report.email,
                "wallpaper": report.wallpaper, "appVersion": report.appVersion, "system": report.system,
            ])
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .failed("The feedback service returned an error. Please try again later.")
            }
            // Apps Script returns {"ok":true}; treat an explicit ok:false as failure.
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               obj["ok"] as? Bool == false {
                return .failed((obj["error"] as? String) ?? "The feedback service rejected the report.")
            }
            return .sent
        } catch {
            return .failed("Couldn't reach the feedback service - check your connection and try again.")
        }
    }

    static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    private static func openMail(_ report: Report) {
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = contactEmail
        let body = "\(report.message)\n\n---\n\(report.category) - Lucid Wallpaper \(appVersion) - macOS \(report.system)"
        comps.queryItems = [
            URLQueryItem(name: "subject", value: "Lucid Wallpaper Feedback - \(report.category)"),
            URLQueryItem(name: "body", value: body),
        ]
        if let url = comps.url { NSWorkspace.shared.open(url) }
    }
}
