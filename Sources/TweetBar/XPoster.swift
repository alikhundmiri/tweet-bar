import AppKit
import CryptoKit
import Foundation

/// X API OAuth 1.0a user-context keys. Saved in a file only you can read (chmod 600).
struct XCredentials: Codable, Equatable {
    var consumerKey = ""
    var consumerSecret = ""
    var accessToken = ""
    var accessSecret = ""

    var isComplete: Bool {
        ![consumerKey, consumerSecret, accessToken, accessSecret].contains {
            $0.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    static let url = Store.dir.appendingPathComponent("x-credentials.json")

    static func load() -> XCredentials {
        guard let d = try? Data(contentsOf: url),
              let c = try? JSONDecoder().decode(XCredentials.self, from: d) else { return XCredentials() }
        return c
    }

    func save() {
        guard let d = try? JSONEncoder().encode(self) else { return }
        try? d.write(to: Self.url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.url.path)
    }
}

enum XPoster {
    static let endpoint = URL(string: "https://api.x.com/2/tweets")!

    /// No API keys needed: opens X's compose screen in the browser with the text filled in.
    static func intentURL(for text: String) -> URL {
        var c = URLComponents(string: "https://x.com/intent/post")!
        // Strict encoding: URLComponents.queryItems leaves '+' unescaped, which X reads as a space.
        c.percentEncodedQuery = "text=" + rfc3986(text)
        return c.url!
    }

    static func openIntent(_ text: String) {
        NSWorkspace.shared.open(intentURL(for: text))
    }

    /// Posts directly via the X API v2. Returns the new tweet's URL.
    static func post(_ text: String, creds: XCredentials) async throws -> URL {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(authHeader(method: "POST", url: endpoint, creds: creds), forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(status),
              let id = (json?["data"] as? [String: Any])?["id"] as? String else {
            let detail = (json?["detail"] as? String)
                ?? (json?["title"] as? String)
                ?? String(data: data, encoding: .utf8) ?? ""
            var msg = "X API error \(status): \(detail)"
            if status == 403 && detail.contains("Project") {
                msg = "X API error 403: your app isn't inside a Project.\nIn the developer portal, create a Project and add this app to it (or create a new app inside a Project and use its keys)."
            } else if status == 403 {
                msg += "\nCheck your app has Read and Write permission, then regenerate the access token."
            }
            throw NSError(domain: "XPoster", code: status, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return URL(string: "https://x.com/i/web/status/\(id)")!
    }

    // MARK: OAuth 1.0a (HMAC-SHA1). The JSON body is not part of the signature.

    static func authHeader(method: String, url: URL, creds: XCredentials,
                           nonce: String = UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                           timestamp: String = String(Int(Date().timeIntervalSince1970))) -> String {
        var params: [String: String] = [
            "oauth_consumer_key": creds.consumerKey.trimmingCharacters(in: .whitespaces),
            "oauth_nonce": nonce,
            "oauth_signature_method": "HMAC-SHA1",
            "oauth_timestamp": timestamp,
            "oauth_token": creds.accessToken.trimmingCharacters(in: .whitespaces),
            "oauth_version": "1.0",
        ]
        // oauth_* keys are unique, so sorting by encoded key is enough.
        let pairs: [String] = params.map { rfc3986($0.key) + "=" + rfc3986($0.value) }
        let paramString = pairs.sorted().joined(separator: "&")
        let base = [method.uppercased(), rfc3986(url.absoluteString), rfc3986(paramString)].joined(separator: "&")
        let key = rfc3986(creds.consumerSecret.trimmingCharacters(in: .whitespaces)) + "&"
            + rfc3986(creds.accessSecret.trimmingCharacters(in: .whitespaces))
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(base.utf8), using: SymmetricKey(data: Data(key.utf8)))
        params["oauth_signature"] = Data(mac).base64EncodedString()
        return "OAuth " + params
            .sorted { $0.key < $1.key }
            .map { "\(rfc3986($0.key))=\"\(rfc3986($0.value))\"" }
            .joined(separator: ", ")
    }

    static func rfc3986(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics.intersection(.init(charactersIn: Unicode.Scalar(0)..<Unicode.Scalar(128)))
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
