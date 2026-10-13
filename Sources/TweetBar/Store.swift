import Foundation
import SwiftUI

struct Draft: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var date = Date()
}

/// App-level state. Lives for the whole app lifetime, so closing the
/// menu bar window never loses what you typed.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()
    nonisolated static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TweetBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private let draftsURL = Store.dir.appendingPathComponent("drafts.json")

    /// Saved to UserDefaults on every keystroke: survives closing the window and quitting.
    @Published var composer: String = UserDefaults.standard.string(forKey: "composer") ?? "" {
        didSet { UserDefaults.standard.set(composer, forKey: "composer") }
    }
    @Published var drafts: [Draft] = [] {
        didSet { saveDrafts() }
    }
    /// Text before the last AI rewrite, so it can be undone.
    @Published var previousText: String?

    init() {
        if let data = try? Data(contentsOf: draftsURL),
           let d = try? JSONDecoder().decode([Draft].self, from: data) {
            drafts = d
        }
    }

    private func saveDrafts() {
        if let data = try? JSONEncoder().encode(drafts) {
            try? data.write(to: draftsURL, options: .atomic)
        }
    }

    func saveDraft() {
        let t = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        drafts.insert(Draft(text: t), at: 0)
        composer = ""
        previousText = nil
    }

    /// Load a draft into the composer. Whatever was in the composer is kept as a draft, not lost.
    func load(_ draft: Draft) {
        let current = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        drafts.removeAll { $0.id == draft.id }
        if !current.isEmpty && current != draft.text {
            drafts.insert(Draft(text: current), at: 0)
        }
        composer = draft.text
        previousText = nil
    }

    func delete(_ draft: Draft) {
        drafts.removeAll { $0.id == draft.id }
    }
}

/// Approximation of X's weighted length: URLs count 23, most non-Latin chars and emoji count 2.
func tweetLength(_ s: String) -> Int {
    var text = s
    var total = 0
    if let re = try? NSRegularExpression(pattern: #"https?://\S+"#) {
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        total += matches.count * 23
        for m in matches.reversed() { text = (text as NSString).replacingCharacters(in: m.range, with: "") }
    }
    for ch in text {
        let v = ch.unicodeScalars.first!.value
        let light = (0...0x10FF).contains(v) || (0x2000...0x200D).contains(v)
            || (0x2010...0x201F).contains(v) || (0x2032...0x2037).contains(v)
        let emoji = ch.unicodeScalars.contains { $0.properties.isEmojiPresentation }
        total += (light && !emoji) ? 1 : 2
    }
    return total
}
