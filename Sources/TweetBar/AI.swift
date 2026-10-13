import Foundation
import FoundationModels

enum AIAction: String, CaseIterable, Identifiable {
    case rewrite = "Rewrite"
    case rephrase = "Rephrase"
    case catchy = "Catchy"
    case shorten = "Shorten"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .rewrite: "pencil.and.outline"
        case .rephrase: "arrow.triangle.2.circlepath"
        case .catchy: "sparkles"
        case .shorten: "scissors"
        }
    }

    var instruction: String {
        switch self {
        case .rewrite: "Rewrite the tweet so it is clearer and better written. Keep the author's meaning and voice."
        case .rephrase: "Rephrase the tweet with different wording but the same meaning and tone."
        case .catchy: "Make the tweet catchier and more engaging, with a strong hook. Keep it authentic, not cringe. Use at most one emoji and no hashtags unless the original had them."
        case .shorten: "Make the tweet shorter and punchier while keeping the key point."
        }
    }
}

@Generable
struct TweetOut {
    @Guide(description: "The final tweet text only. No preamble, no quotes around it, no explanation.")
    var text: String
}

enum AIError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let r): "Apple Intelligence unavailable: \(r)" }
    }
}

enum AI {
    static var availabilityMessage: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in System Settings."
        case .unavailable(.deviceNotEligible): return "This Mac doesn't support Apple Intelligence."
        case .unavailable(.modelNotReady): return "Apple Intelligence model is still downloading."
        case .unavailable(let other): return "Apple Intelligence unavailable (\(other))."
        }
    }

    static func transform(_ text: String, _ action: AIAction) async throws -> String {
        if let msg = availabilityMessage { throw AIError.unavailable(msg) }
        let session = LanguageModelSession(instructions: """
            You edit tweets for X (Twitter). \(action.instruction)
            The result MUST be 280 characters or fewer. Write in the same language as the input.
            """)
        var out = try await session.respond(to: text, generating: TweetOut.self).content.text
        if tweetLength(out) > 280 {
            out = try await session.respond(
                to: "That is too long. Shorten it to under 260 characters.",
                generating: TweetOut.self
            ).content.text
        }
        return out.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "\"“”")))
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? LanguageModelSession.GenerationError {
            switch e {
            case .guardrailViolation: return "Apple's safety filter blocked this text. Try different wording."
            case .exceededContextWindowSize: return "Text is too long for the on-device model."
            case .unsupportedLanguageOrLocale: return "This language isn't supported by the on-device model."
            case .rateLimited: return "The model is busy. Try again in a moment."
            default: return e.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
