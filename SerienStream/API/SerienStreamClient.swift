import Foundation

final class SerienStreamClient {
    static let shared = SerienStreamClient()

    private static let domainKey = "serienstream.domain"
    static let domains = ["https://serienstream.to", "https://serienstream.cx", "http://186.2.175.5"]

    var baseURL: String {
        get { UserDefaults.standard.string(forKey: Self.domainKey) ?? Self.domains[0] }
        set { UserDefaults.standard.set(newValue, forKey: Self.domainKey) }
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 25
        return URLSession(configuration: config)
    }()

    private let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    // MARK: - Low level

    func fetchHTML(_ path: String) async throws -> String {
        var lastError: Error = AppError.network("unbekannt")
        let tried = [baseURL] + Self.domains.filter { $0 != baseURL }
        for base in tried {
            guard let url = URL(string: base + path) else { continue }
            var request = URLRequest(url: url)
            request.setValue(ua, forHTTPHeaderField: "User-Agent")
            request.setValue(base + "/", forHTTPHeaderField: "Referer")
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    lastError = AppError.network("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    continue
                }
                guard let html = String(data: data, encoding: .utf8) else {
                    lastError = AppError.parsing("Ungültige Kodierung")
                    continue
                }
                return html
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    // MARK: - HTML helpers

    private func matches(_ pattern: String, in text: String, options: NSRegularExpression.Options = [.dotMatchesLineSeparators]) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).compactMap { i -> String? in
                guard let r = Range(match.range(at: i), in: text) else { return nil }
                return String(text[r])
            }
        }
    }

    private func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
         .replacingOccurrences(of: "&lt;", with: "<")
         .replacingOccurrences(of: "&gt;", with: ">")
         .replacingOccurrences(of: "&quot;", with: "\"")
         .replacingOccurrences(of: "&#039;", with: "'")
         .replacingOccurrences(of: "&apos;", with: "'")
    }

    private func absoluteURL(_ path: String) -> URL? {
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: baseURL + path)
    }

    // MARK: - Catalog

    /// Volle A-Z Serienliste von /serien
    func fetchCatalog() async throws -> [Series] {
        let html = try await fetchHTML("/serien")
        // <li class="series-item" data-search="..."> <a href="/serie/slug">Title</a> </li>
        let rows = matches(#"<li class="series-item"[^>]*data-search="([^"]*)"[^>]*>\s*<a href="/serie/([^"]+)"[^>]*>(.*?)</a>"#, in: html)
        return rows.compactMap { row in
            guard row.count >= 4 else { return nil }
            return Series(slug: row[2], title: decodeEntities(row[3]).trimmingCharacters(in: .whitespacesAndNewlines), searchText: decodeEntities(row[1]).lowercased(), coverURL: nil)
        }
    }

    /// Beliebte Serien mit Covern
    func fetchPopular() async throws -> [Series] {
        let html = try await fetchHTML("/beliebte-serien")
        return parseSeriesCards(html)
    }

    /// Genre-Listing (gleiche Card-Struktur)
    func fetchGenre(_ genre: String) async throws -> [Series] {
        let html = try await fetchHTML("/genre/\(genre)")
        return parseSeriesCards(html)
    }

    private func parseSeriesCards(_ html: String) -> [Series] {
        // Jede Card: <a ... href="/serie/slug" class="show-card ..."> ... <img data-src="/media/images/channel/desktop/slug-hash?format=jpg"
        let cards = matches(#"href="(/serie/[^"]+)"[^>]*class="[^"]*show-card[\s\S]*?</a>"#, in: html)
        var seen = Set<String>()
        var result: [Series] = []
        for card in cards {
            guard card.count >= 2 else { continue }
            let cardHTML = card[0]
            var slug = String(card[1].dropFirst("/serie/".count))
            // Hrefs verweisen oft auf /serie/slug/staffel-N → auf Serien-Slug kürzen
            if let range = slug.range(of: #"/staffel-\d+"#, options: .regularExpression) {
                slug = String(slug[..<range.lowerBound])
            }
            guard !seen.contains(slug) else { continue }
            seen.insert(slug)
            var cover: URL?
            if let img = matches(#"(?:data-src|src)="(/media/images/channel/desktop/[^"]*?format=jpg)""#, in: cardHTML).first, img.count >= 2 {
                cover = absoluteURL(img[1])
            } else if let img = matches(#"(?:data-src|src)="(/media/images/[^"]+)""#, in: cardHTML).first, img.count >= 2 {
                cover = absoluteURL(img[1])
            }
            var title = slug.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
            if let alt = matches(#"alt="([^"]+)""#, in: cardHTML).first, alt.count >= 2, !alt[1].isEmpty {
                title = decodeEntities(alt[1])
            }
            result.append(Series(slug: slug, title: title, searchText: title.lowercased(), coverURL: cover))
        }
        return result
    }

    // MARK: - Detail

    func fetchDetail(slug: String) async throws -> SeriesDetail {
        let html = try await fetchHTML("/serie/\(slug)")

        var detail = SeriesDetail(slug: slug, title: slug, description: "", genres: [], coverURL: nil, backdropURL: nil, seasons: [])

        if let t = matches(#"<h1[^>]*>(.*?)</h1>"#, in: html).first, t.count >= 2 {
            detail.title = decodeEntities(stripTags(t[1])).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let img = matches(#"(?:data-src|src)="(/media/images/channel/desktop/[^"]+)""#, in: html).first, img.count >= 2 {
            detail.coverURL = absoluteURL(img[1])
        }
        if let img = matches(#"(?:data-src|src)="(/media/images/backdrop/desktop/[^"]+)""#, in: html).first, img.count >= 2 {
            detail.backdropURL = absoluteURL(img[1])
        }
        let genreRows = matches(#"href="/genre/([^"]+)""#, in: html)
        var genres: [String] = []
        for g in genreRows where g.count >= 2 {
            if !genres.contains(g[1]) { genres.append(g[1]) }
        }
        detail.genres = genres

        let seasonRows = matches(#"/serie/[^"/]+/staffel-(\d+)"#, in: html)
        var seasons = Set<Int>()
        for s in seasonRows where s.count >= 2 {
            if let n = Int(s[1]) { seasons.insert(n) }
        }
        detail.seasons = seasons.sorted()

        // Beschreibung: typischerweise ein <p> im Info-Bereich
        if let d = matches(#"<div[^>]*class="[^"]*description[^"]*"[^>]*>([\s\S]*?)</div>"#, in: html).first, d.count >= 2 {
            detail.description = decodeEntities(stripTags(d[1])).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return detail
    }

    private func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    // MARK: - Episodes

    func fetchEpisodes(slug: String, season: Int) async throws -> [EpisodeRef] {
        let html = try await fetchHTML("/serie/\(slug)/staffel-\(season)")
        let rows = matches(#"/serie/[^"/]+/staffel-\(season)/episode-(\d+)"#, in: html)
        var nums = Set<Int>()
        for r in rows where r.count >= 2 {
            if let n = Int(r[1]) { nums.insert(n) }
        }
        return nums.sorted().map { EpisodeRef(season: season, episode: $0, seriesSlug: slug, title: nil) }
    }

    // MARK: - Episode links (Hoster)

    func fetchEpisodeLinks(_ ep: EpisodeRef) async throws -> [EpisodeLink] {
        let html = try await fetchHTML(ep.path)
        // <button class="link-box ..." data-link-id=".." data-play-url="/r?t=.." data-provider-name=".." data-language-label=".."
        let rows = matches(#"<button[^>]*class="[^"]*link-box[^"]*"[^>]*>"#, in: html)
        var links: [EpisodeLink] = []
        for row in rows {
            guard let tag = row.first else { continue }
            guard let linkId = attr("data-link-id", in: tag),
                  let playUrl = attr("data-play-url", in: tag) else { continue }
            let provider = attr("data-provider-name", in: tag) ?? "Unbekannt"
            let lang = attr("data-language-label", in: tag) ?? "Deutsch"
            links.append(EpisodeLink(linkId: linkId, providerName: provider, languageLabel: lang, playPath: decodeEntities(playUrl)))
        }
        return links
    }

    private func attr(_ name: String, in tag: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: name + #"="([^"]*)""#) else { return nil }
        let range = NSRange(tag.startIndex..., in: tag)
        guard let m = regex.firstMatch(in: tag, range: range), m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: tag) else { return nil }
        return String(tag[r])
    }
}
