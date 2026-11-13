import SwiftUI
import AppKit

/// In-app feedback form. Sends a report to the developer's "Wallpaper Issues" Drive folder
/// (via the Apps Script endpoint), or falls back to an email draft if none is configured.
struct FeedbackView: View {
    @EnvironmentObject private var model: AppModel
    let onClose: () -> Void

    @State private var category = "Bug"
    @State private var message = ""
    @State private var email = ""
    @State private var sending = false
    @State private var outcome: Feedback.Outcome?

    private let categories = ["Bug", "Idea", "Other"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send Feedback").font(.title2.bold())

            Picker("", selection: $category) {
                ForEach(categories, id: \.self) { Text($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ZStack(alignment: .topLeading) {
                TextEditor(text: $message)
                    .font(.body)
                    .frame(height: 130)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
                if message.isEmpty {
                    Text(placeholder).foregroundStyle(.secondary).padding(.horizontal, 9).padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }

            TextField("Your email (optional, so we can reply)", text: $email)
                .textFieldStyle(.roundedBorder)

            if let outcome { resultRow(outcome) }

            HStack {
                Text(Feedback.endpoint == nil
                     ? "No service configured - this opens your mail app."
                     : "Sent privately to the developer.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button(action: submit) {
                    if sending { ProgressView().controlSize(.small) } else { Text("Send") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty || sending)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var placeholder: String {
        switch category {
        case "Bug": return "What happened, and what did you expect? Steps to reproduce help a lot."
        case "Idea": return "What would you like Lucid Wallpaper to do?"
        default: return "Tell us anything…"
        }
    }

    @ViewBuilder private func resultRow(_ outcome: Feedback.Outcome) -> some View {
        switch outcome {
        case .sent:
            Label("Thanks! Your feedback was sent.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.callout)
        case .openedMail:
            Label("Opened your mail app to finish sending.", systemImage: "envelope")
                .foregroundStyle(.secondary).font(.callout)
        case .failed(let why):
            Label(why, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.callout)
        }
    }

    private func submit() {
        sending = true
        outcome = nil
        let report = Feedback.makeReport(category: category, message: message, email: email,
                                         wallpaper: model.currentItem?.title ?? "(none)")
        Task {
            let result = await Feedback.send(report)
            sending = false
            outcome = result
            if case .failed = result { return }   // keep the form open so they can retry
            // Success (.sent / .openedMail): briefly show the confirmation, then close.
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            onClose()
        }
    }
}

/// Hosts the feedback form in a small window, shown from the menu bar / menus / Settings.
@MainActor
final class FeedbackWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) { self.model = model }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Send Feedback"
            w.isReleasedWhenClosed = false
            window = w
        }
        // Recreate the content each open so the form starts fresh.
        window?.contentViewController = NSHostingController(
            rootView: FeedbackView(onClose: { [weak self] in self?.close() }).environmentObject(model))
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }
}
