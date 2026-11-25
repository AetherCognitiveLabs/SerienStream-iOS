import Foundation

/// Zieht aus Hoster-Embed-URLs (VOE, Doodstream, Streamtape, …) die Direct-Stream-URL.
final class HosterExtractor {
    static let shared = HosterExtractor()

    private let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    enum Hoster: String {
        case voe, doodstream, streamtape, vidoza, mixdrop, speedfiles, unknown

        static func detect(_ url: URL) -> Hoster {
            let host = (url.host ?? "").lowercased()
            if host.contains("voe") || host.contains("markofdatk") || host.contains("metagnathtuggers") { return .voe }
            if host.contains("dood") || host.contains("d000d") || host.contains("do7go") || host.contains("doodstream") { return .doodstream }
            if host.contains("streamtape") || host.contains("strtape") || host.contains("stape") { return .streamtape }
            if host.contains("vidoza") { return .vidoza }
            if host.contains("mixdrop") { return .mixdrop }
            if host.contains("speedfiles") { return .speedfiles }
            return .unknown
        }
    }

    func extract(embedURL: URL) async throws -> StreamResult {
        let hoster = Hoster.detect(embedURL)
        switch hoster {
        case .voe: return try await extractVOE(embedURL)
        case .doodstream: return try await extractDoodstream(embedURL)
        case .streamtape: return try await extractStreamtape(embedURL)
        default: return try await extractGeneric(embedURL)
        }
    }

    private func fetch(_ url: URL, referer: String? = nil) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        if let referer { request.setValue(referer, forHTTPHeaderField: "Referer") }
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw AppError.extractionFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0) bei \(url.host ?? "")")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func headers(for embedURL: URL) -> [String: String] {
        var h = ["User-Agent": ua]
        if let scheme = embedURL.scheme, let host = embedURL.host {
            h["Referer"] = "\(scheme)://\(host)/"
        }
        return h
    }

    // MARK: - VOE

    private func extractVOE(_ embedURL: URL) async throws -> StreamResult {
        let html = try await fetch(embedURL)
        // VOE versteckt 'hls' als base64 in Script-Tags
        let patterns = [
            #"'hls'\s*:\s*'([^']+)'"#,
            #""hls"\s*:\s*"([^"]+)""#,
            #"'hls'\s*:\s*"([^"]+)""#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               m.numberOfRanges >= 2,
               let r = Range(m.range(at: 1), in: html) {
                var candidate = String(html[r])
                if !candidate.hasPrefix("http"), let decoded = Data(base64Encoded: candidate),
                   let decodedStr = String(data: decoded, encoding: .utf8), decodedStr.hasPrefix("http") {
                    candidate = decodedStr
                }
                if candidate.hasPrefix("http"), let streamURL = URL(string: candidate) {
                    return StreamResult(streamURL: streamURL, headers: headers(for: embedURL))
                }
            }
        }
        // Fallback: generisch
        return try await extractGeneric(embedURL, html: html)
    }

    // MARK: - Doodstream

    private func extractDoodstream(_ embedURL: URL) async throws -> StreamResult {
        let html = try await fetch(embedURL)
        guard let regex = try? NSRegularExpression(pattern: #"/pass_md5/[^'"]+"#),
              let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 0), in: html) else {
            return try await extractGeneric(embedURL, html: html)
        }
        let passPath = String(html[r])
        guard let base = embedURL.host, let scheme = embedURL.scheme,
              let passURL = URL(string: "\(scheme)://\(base)\(passPath)") else {
            throw AppError.extractionFailed("Doodstream: pass_md5 nicht auflösbar")
        }
        let passResponse = try await fetch(passURL, referer: embedURL.absoluteString)
        // Token suffix: 10 random chars, doodstream expects ?token=...&expiry=
        let token = String((0..<10).compactMap { _ in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement() })
        let expiry = Int(Date().timeIntervalSince1970 * 1000)
        let finalString = "\(passResponse)\(token)?token=\(passPath.split(separator: "/").last ?? "")&expiry=\(expiry)"
        guard let streamURL = URL(string: finalString) else {
            throw AppError.extractionFailed("Doodstream: finale URL ungültig")
        }
        return StreamResult(streamURL: streamURL, headers: headers(for: embedURL))
    }

    // MARK: - Streamtape

    private func extractStreamtape(_ embedURL: URL) async throws -> StreamResult {
        let html = try await fetch(embedURL)
        // document.getElementById('ideoooolink').innerHTML = "..." + substring-Tricks
        guard let regex = try? NSRegularExpression(pattern: #"getElementById\('ideoooolink'\)[\s\S]{0,400}?innerHTML\s*=\s*(.*?);"#),
              let m = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else {
            return try await extractGeneric(embedURL, html: html)
        }
        let expr = String(html[r])
        // Auswertung der konkatenierten String-Teile mit optionalen .substring()-Aufrufen
        var result = ""
        let partRegex = try NSRegularExpression(pattern: #"'([^']*)'(?:\.substring\((\d+)(?:,(\d+))?\))?"#)
        let matches = partRegex.matches(in: expr, range: NSRange(expr.startIndex..., in: expr))
        for part in matches {
            guard let strR = Range(part.range(at: 1), in: expr) else { continue }
            var piece = String(expr[strR])
            if part.range(at: 2).location != NSNotFound, let startR = Range(part.range(at: 2), in: expr),
               let start = Int(expr[startR]) {
                let idx = piece.index(piece.startIndex, offsetBy: min(start, piece.count))
                piece = String(piece[idx...])
            }
            result += piece
        }
        if result.hasPrefix("//") { result = "https:" + result }
        if !result.hasPrefix("http") { result = "https://" + result }
        guard let streamURL = URL(string: result), result.contains("http") else {
            throw AppError.extractionFailed("Streamtape: keine URL rekonstruiert")
        }
        return StreamResult(streamURL: streamURL, headers: headers(for: embedURL))
    }

    // MARK: - Generisch

    private func extractGeneric(_ embedURL: URL, html: String? = nil) async throws -> StreamResult {
        let content: String
        if let html {
            content = html
        } else {
            content = try await fetch(embedURL)
        }
        // m3u8/mp4 URLs finden (auch escaped)
        let patterns = [
            #"https?://[^\s"'\\]+\.m3u8[^\s"'\\]*"#,
            #"https?://[^\s"'\\]+\.mp4[^\s"'\\]*"#,
            #"https?:\\/\\/[^\s"']+\.m3u8[^\s"']*"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let m = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
               let r = Range(m.range(at: 0), in: content) {
                var candidate = String(content[r])
                    .replacingOccurrences(of: "\\/", with: "/")
                    .replacingOccurrences(of: "\\u0026", with: "&")
                candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                if let streamURL = URL(string: candidate) {
                    return StreamResult(streamURL: streamURL, headers: headers(for: embedURL))
                }
            }
        }
        throw AppError.extractionFailed("Kein Direct-Stream bei \(embedURL.host ?? "Hoster") gefunden")
    }
}
