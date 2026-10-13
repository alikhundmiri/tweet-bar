import AppKit
import ServiceManagement
import SwiftUI

@main
struct TweetBarApp: App {
    @NSApplicationDelegateAdaptor(DebugWindow.self) var debug
    @StateObject private var store = Store.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(store)
        } label: {
            Image(systemName: "bubble.left.and.text.bubble.right")
        }
        .menuBarExtraStyle(.window)
    }
}

/// TWEETBAR_DEBUG_TAB=compose|drafts|settings opens the panel in a normal window (for screenshots).
final class DebugWindow: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    func applicationDidFinishLaunching(_ n: Notification) {
        guard let t = ProcessInfo.processInfo.environment["TWEETBAR_DEBUG_TAB"] else { return }
        let view = PanelView(tab: t == "drafts" ? .drafts : .compose, showSettings: t == "settings")
            .environmentObject(Store.shared)
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.setFrameTopLeftPoint(NSPoint(x: 100, y: (NSScreen.main?.frame.height ?? 900) - 100))
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
        window = w
    }
}

enum Tab: String, CaseIterable { case compose = "Compose", drafts = "Drafts" }

struct PanelView: View {
    @EnvironmentObject var store: Store
    @State var tab: Tab = .compose
    @State var showSettings = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("", selection: $tab) {
                    Text("Compose").tag(Tab.compose)
                    Text("Drafts (\(store.drafts.count))").tag(Tab.drafts)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(showSettings)

                Button { showSettings.toggle() } label: {
                    Image(systemName: showSettings ? "xmark.circle.fill" : "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }

            if showSettings {
                SettingsView()
            } else if tab == .compose {
                ComposeView()
            } else {
                DraftsView(onLoad: { tab = .compose })
            }
        }
        .padding(12)
        .frame(width: 400, height: 380)
        .onAppear { NSApp.activate() }
    }
}

// MARK: - Compose

struct ComposeView: View {
    @EnvironmentObject var store: Store
    @FocusState private var focused: Bool
    @State private var busy: AIAction?
    @State private var sending = false
    @State private var message: (text: String, isError: Bool, link: URL?)?
    @State private var awaitingBrowser = false
    @AppStorage("directPost") private var directPost = false

    private var length: Int { tweetLength(store.composer) }
    private var isEmpty: Bool { store.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var working: Bool { busy != nil || sending }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $store.composer)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .disabled(working)
                if store.composer.isEmpty {
                    Text("What's happening?")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

            HStack(spacing: 6) {
                ForEach(AIAction.allCases) { action in
                    Button { runAI(action) } label: {
                        if busy == action {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(action.rawValue, systemImage: action.symbol)
                        }
                    }
                    .controlSize(.small)
                    .disabled(isEmpty || working)
                }
                Spacer(minLength: 0)
                if store.previousText != nil {
                    Button { undoAI() } label: { Image(systemName: "arrow.uturn.backward") }
                        .controlSize(.small)
                        .help("Undo AI change")
                        .disabled(working)
                }
            }
            .labelStyle(.titleAndIcon)

            if let m = message {
                HStack(alignment: .top, spacing: 6) {
                    Text(m.text)
                        .font(.caption)
                        .foregroundStyle(m.isError ? .red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let link = m.link {
                        Link("View", destination: link).font(.caption)
                    }
                    Spacer(minLength: 0)
                    if awaitingBrowser {
                        Button("Posted, clear it") {
                            store.composer = ""; store.previousText = nil
                            awaitingBrowser = false; message = nil
                        }
                        .controlSize(.small)
                    }
                }
            }

            HStack {
                Button { store.saveDraft(); message = ("Saved to drafts.", false, nil) } label: {
                    Label("Draft", systemImage: "tray.and.arrow.down")
                }
                .disabled(isEmpty || working)

                Spacer()

                Button {
                    store.composer = ""; store.previousText = nil
                    awaitingBrowser = false; message = nil
                } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.borderless)
                .help("Clear")
                .disabled(isEmpty || working)

                Text("\(280 - length)")
                    .font(.system(.callout, design: .rounded).monospacedDigit())
                    .foregroundStyle(length > 280 ? .red : length > 260 ? .orange : .secondary)

                Button { send() } label: {
                    if sending { ProgressView().controlSize(.small) } else { Text("Send") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isEmpty || length > 280 || working)
                .help(directPost ? "Post to X via API (⌘↩)" : "Open in X to post, free (⌘↩)")
            }
        }
        .onAppear { focused = true }
        .onChange(of: store.composer) { if !working { awaitingBrowser = false } }
    }

    private func runAI(_ action: AIAction) {
        let original = store.composer
        busy = action
        message = nil
        Task {
            defer { busy = nil }
            do {
                let result = try await AI.transform(original, action)
                store.previousText = original
                store.composer = result
            } catch {
                message = (AI.describe(error), true, nil)
            }
        }
    }

    private func undoAI() {
        if let p = store.previousText { store.composer = p; store.previousText = nil }
    }

    private func send() {
        let text = store.composer.trimmingCharacters(in: .whitespacesAndNewlines)
        let creds = XCredentials.load()
        guard directPost, creds.isComplete else {
            // No API keys: hand off to X's web composer, keep the text until the user confirms.
            XPoster.openIntent(text)
            message = ("Opened in X. Click Post there.", false, nil)
            awaitingBrowser = true
            return
        }
        sending = true
        message = nil
        Task {
            defer { sending = false }
            do {
                let url = try await XPoster.post(text, creds: creds)
                store.composer = ""
                store.previousText = nil
                message = ("Posted.", false, url)
            } catch {
                message = (error.localizedDescription, true, nil)
            }
        }
    }
}

// MARK: - Drafts

struct DraftsView: View {
    @EnvironmentObject var store: Store
    var onLoad: () -> Void

    var body: some View {
        if store.drafts.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray").font(.largeTitle).foregroundStyle(.tertiary)
                Text("No drafts yet").foregroundStyle(.secondary)
                Text("Hit Draft in Compose to save one here.").font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(store.drafts) { d in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(d.text).lineLimit(4).font(.system(size: 13))
                        HStack {
                            Text(d.date, format: .relative(presentation: .named))
                                .font(.caption2).foregroundStyle(.tertiary)
                            Spacer()
                            Button("Edit") { store.load(d); onLoad() }
                                .controlSize(.small)
                            Button(role: .destructive) { store.delete(d) } label: {
                                Image(systemName: "trash")
                            }
                            .controlSize(.small)
                            .help("Delete draft")
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { store.load(d); onLoad() }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @State private var creds = XCredentials.load()
    @State private var saved = false
    @AppStorage("directPost") private var directPost = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Send mode").font(.headline)
                Picker("", selection: $directPost) {
                    Text("Free (browser)").tag(false)
                    Text("Direct (X API)").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!creds.isComplete && !directPost)
                Text(directPost
                     ? "Send posts straight from here. X charges your developer credits per post (more for posts with links)."
                     : "Send opens X in your browser with the tweet filled in. Free, one extra click on Post.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("X API keys (for Direct mode)").font(.subheadline.weight(.semibold)).padding(.top, 4)
                Text("From an app inside a Project at developer.x.com, with **Read and Write** permission. Generate the Access Token *after* setting that permission.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Group {
                    TextField("API Key (consumer key)", text: $creds.consumerKey)
                    SecureField("API Key Secret", text: $creds.consumerSecret)
                    TextField("Access Token", text: $creds.accessToken)
                    SecureField("Access Token Secret", text: $creds.accessSecret)
                }
                .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save keys") { creds.save(); saved = true }
                    if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
                    Spacer()
                    Button("Remove keys", role: .destructive) {
                        creds = XCredentials(); creds.save(); directPost = false
                    }
                    .disabled(creds == XCredentials())
                }

                Divider()

                if let msg = AI.availabilityMessage {
                    Label(msg, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                } else {
                    Label("Apple Intelligence ready (on-device)", systemImage: "apple.intelligence")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = "Move TweetBar to /Applications first. (\(error.localizedDescription))"
                        }
                    }
                if let e = loginError { Text(e).font(.caption).foregroundStyle(.red) }

                HStack {
                    Spacer()
                    Button("Quit TweetBar") { NSApp.terminate(nil) }
                }
            }
        }
        .onChange(of: creds) { saved = false }
    }
}
