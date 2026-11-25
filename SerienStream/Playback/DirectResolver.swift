import Foundation

/// Löst die Hoster-Embed-URL rein über HTTP auf — ganz ohne Turnstile/WebView-Gate.
/// Das s.to-"Sicherheitsgate" ist nur UI: POST /r mit CSRF-Token + signiertem
/// t-Parameter liefert direkt den 302-Redirect zum Hoster.
final class DirectResolver {
    static let shared = DirectResolver()

    private let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil) // Redirects nicht folgen — wir wollen den Location-Header
        }
    }

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }()

    enum ResolveError: LocalizedError {
        case noToken
        case noRedirect
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .noToken: return "Kein Token auf der Episodenseite gefunden"
            case .noRedirect: return "Server hat keinen Hoster-Redirect geliefert"
            case .httpError(let code): return "HTTP \(code) bei der Stream-Auflösung"
            }
        }
    }

    /// Gibt die Hoster-Embed-URL zurück (z.B. https://voe.sx/e/…).
    func resolve(episode: EpisodeRef, link: EpisodeLink) async throws -> URL {
        let base = SerienStreamClient.shared.baseURL
        guard let pageURL = URL(string: base + episode.path) else {
            throw ResolveError.noToken
        }

        // 1. Episodenseite laden (setzt Cookies, liefert CSRF-Token)
        var pageReq = URLRequest(url: pageURL)
        pageReq.setValue(ua, forHTTPHeaderField: "User-Agent")
        let (pageData, pageResp) = try await session.data(for: pageReq)
        guard let http = pageResp as? HTTPURLResponse, http.statusCode == 200 else {
            throw ResolveError.httpError((pageResp as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let html = String(data: pageData, encoding: .utf8) else {
            throw ResolveError.noToken
        }

        guard let csrf = capture(#"name="csrf-token" content="([^"]+)""#, in: html) else {
            throw ResolveError.noToken
        }
        // _token aus dem player-prepare-form (Fallback: csrf)
        let formToken = capture(#"id="player-prepare-form"[\s\S]*?name="_token" value="([^"]+)""#, in: html)
            ?? capture(#"name="_token" value="([^"]+)""#, in: html)
            ?? csrf

        // t-Parameter: aus dem data-play-url des konkreten Hosters oder dem player-iframe
        var tParam: String?
        if let playURL = link.playPath as String?, let tRange = playURL.range(of: "t=") {
            tParam = String(playURL[tRange.upperBound...])
        }
        if tParam == nil || tParam?.isEmpty == true {
            tParam = capture(#"player-iframe"[^>]*src="/r\?t=([^"]+)""#, in: html)
        }
        // t bleibt percent-enkodiert wie im HTML — wird so in den POST-Body übernommen
        guard let t = tParam, !t.isEmpty else {
            throw ResolveError.noToken
        }

        // 2. POST /r — liefert 302 zum Hoster
        guard let rURL = URL(string: base + "/r") else { throw ResolveError.noRedirect }
        var post = URLRequest(url: rURL)
        post.httpMethod = "POST"
        post.setValue(ua, forHTTPHeaderField: "User-Agent")
        post.setValue(base + episode.path, forHTTPHeaderField: "Referer")
        post.setValue(csrf, forHTTPHeaderField: "X-CSRF-TOKEN")
        post.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "_token=\(formToken)&t=\(t)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        // t selbst darf nicht doppelt enkodiert werden — baue Body manuell
        let encToken = formToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? formToken
        post.httpBody = "_token=\(encToken)&t=\(t)".data(using: .utf8)
        _ = body

        let (_, postResp) = try await session.data(for: post)
        guard let postHTTP = postResp as? HTTPURLResponse else {
            throw ResolveError.noRedirect
        }
        if (300..<400).contains(postHTTP.statusCode), let location = postHTTP.value(forHTTPHeaderField: "Location"), let embed = URL(string: location) {
            DLog("Direct-Resolver: \(link.providerName) → \(embed.absoluteString)", category: "player")
            return embed
        }
        // Manche Antworten liefern 200 mit meta-refresh
        throw ResolveError.httpError(postHTTP.statusCode)
    }

    private func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
