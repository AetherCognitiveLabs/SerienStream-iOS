import Foundation

final class SerienStreamClient {
    static let shared = SerienStreamClient()

    private static let domainKey = "serienstream.domain"
    private static let manualDomainKey = "serienstream.domain.manual"

    struct Endpoint: Hashable {
        let name: String
        let url: String
        let note: String
    }

    static let endpoints: [Endpoint] = [
        Endpoint(name: "Proxy (direkt)", url: "http://186.2.175.5", note: "Funktioniert ohne DNS-Umstellung"),
        Endpoint(name: "SerienStream.to", url: "https://serienstream.to", note: "Hauptdomain — oft ISP-gesperrt"),
        Endpoint(name: "SerienStream.cx", url: "https://serienstream.cx", note: "Alternative Domain"),
    ]

    static var domains: [String] { endpoints.map { $0.url } }

    /// Aktuell gewählte Basis-URL. Default: Proxy (laut Nutzer der einzig zuverlässige Weg).
    var baseURL: String {
        get { UserDefaults.standard.string(forKey: Self.domainKey) ?? Self.endpoints[0].url }
        set { UserDefaults.standard.set(newValue, forKey: Self.domainKey) }
    }

    var manualOverride: Bool {
        get { UserDefaults.standard.bool(forKey: Self.manualDomainKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.manualDomainKey) }
    }

    func selectEndpoint(_ url: String, manual: Bool) {
        baseURL = url
        manualOverride = manual
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    // MARK: - Endpoint probing

    /// Prüft einen Endpoint mit kurzem Timeout. true wenn erreichbar.
    func probe(_ endpointURL: String) async -> Bool {
        guard let url = URL(string: endpointURL + "/") else { return false }
        var request = URLRequest(url: url)
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            let ok = (200..<400).contains(http.statusCode)
            DLog("Probe \(endpointURL): \(http.statusCode)", category: "probe")
            return ok
        } catch {
            DLog("Probe \(endpointURL): \(error.localizedDescription)", category: "probe")
            return false
        }
    }

    /// Findet den ersten erreichbaren Endpoint und setzt ihn (wenn kein manueller Override).
    @discardableResult
    func autoSelectEndpoint() async -> String {
        let results = await withTaskGroup(of: (String, Bool).self) { group -> [String: Bool] in
            for ep in Self.endpoints {
                group.addTask { (ep.url, await self.probe(ep.url)) }
            }
            var map: [String: Bool] = [:]
            for await (url, ok) in group { map[url] = ok }
            return map
        }
        // Reihenfolge der Endpoint-Liste = Priorität
        for ep in Self.endpoints where results[ep.url] == true {
            if !manualOverride { baseURL = ep.url }
            return ep.url
        }
        return baseURL
    }

    func probeAll() async -> [(endpoint: Endpoint, reachable: Bool)] {
        var out: [(Endpoint, Bool)] = []
        for ep in Self.endpoints {
            let ok = await probe(ep.url)
            out.append((ep, ok))
        }
        return out
    }

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
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    DLog("HTTP \(code) für \(base)\(path)", category: "net")
                    lastError = AppError.network("HTTP \(code)")
                    continue
                }
                guard let html = String(data: data, encoding: .utf8) else {
                    lastError = AppError.parsing("Ungültige Kodierung")
                    continue
                }
                DLog("OK \(base)\(path) (\(data.count) bytes)", category: "net")
                return html
            } catch {
                DLog("Fehler \(base)\(path): \(error.localizedDescription)", category: "net")
                lastError = error
            }
        }
        throw lastError
    }

    /// Baut eine absolute URL relativ zum aktiven Endpoint.
    func absoluteURL(_ path: String) -> URL? {
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: baseURL + path)
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

    private func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    // MARK: - Catalog

    /// Volle A-Z Serienliste von /serien
    func fetchCatalog() async throws -> [Series] {
        let html = try await fetchHTML("/serien")
        let rows = matches(#"<li class="series-item"[^>]*data-search="([^"]*)"[^>]*>\s*<a href="/serie/([^"]+)"[^>]*>(.*?)</a>"#, in: html)
        return rows.compactMap { row in
            guard row.count >= 4 else { return nil }
            return Series(slug: row[2], title: decodeEntities(row[3]).trimmingCharacters(in: .whitespacesAndNewlines), searchText: decodeEntities(row[1]).lowercased(), coverURL: nil)
        }
    }

    // MARK: - Popular sections

    struct PopularSection {
        let title: String
        var series: [Series]
    }

    /// /beliebte-serien — enthält mehrere Sektionen (Neue Staffeln, Beliebte Serien, …)
    func fetchPopularSections() async throws -> [PopularSection] {
        let html = try await fetchHTML("/beliebte-serien")
        // Sektionen an <h2>-Überschriften schneiden
        let h2s = matches(#"<h2[^>]*>([\s\S]*?)</h2>"#, in: html)
        var sections: [PopularSection] = []
        var positions: [(String, Int)] = []
        for h in h2s where h.count >= 2 {
            let title = decodeEntities(stripTags(h[1])).trimmingCharacters(in: .whitespacesAndNewlines)
            if let r = html.range(of: h[0]) {
                positions.append((title, html.distance(from: html.startIndex, to: r.lowerBound)))
            }
        }
        positions = positions.sorted { $0.1 < $1.1 }
        for (i, pos) in positions.enumerated() {
            let start = pos.1
            let end = i + 1 < positions.count ? positions[i + 1].1 : html.count
            let startIdx = html.index(html.startIndex, offsetBy: start)
            let endIdx = html.index(html.startIndex, offsetBy: min(end, html.count))
            let slice = String(html[startIdx..<endIdx])
            let cards = parseSeriesCards(slice)
            if !cards.isEmpty {
                sections.append(PopularSection(title: pos.0, series: cards))
            }
        }
        if sections.isEmpty {
            let cards = parseSeriesCards(html)
            if !cards.isEmpty {
                sections.append(PopularSection(title: "Beliebte Serien", series: cards))
            }
        }
        return sections
    }

    func fetchGenre(_ genre: String) async throws -> [Series] {
        let html = try await fetchHTML("/genre/\(genre)")
        return parseSeriesCards(html)
    }

    func parseSeriesCards(_ html: String) -> [Series] {
        let cards = matches(#"href="(/serie/[^"]+)"[^>]*class="[^"]*show-card[\s\S]*?</a>"#, in: html)
        var seen = Set<String>()
        var result: [Series] = []
        for card in cards {
            guard card.count >= 2 else { continue }
            let cardHTML = card[0]
            var slug = String(card[1].dropFirst("/serie/".count))
            if let range = slug.range(of: #"/staffel-\d+"#, options: .regularExpression) {
                slug = String(slug[..<range.lowerBound])
            }
            guard !slug.isEmpty, !seen.contains(slug) else { continue }
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

    // MARK: - Homepage Hero

    struct HeroSlide {
        let slug: String
        let title: String
        let backdropURL: URL?
    }

    /// Echte Homepage-Hero-Slides (Backdrop + Titel) von /
    func fetchHomeHeroes() async throws -> [HeroSlide] {
        let html = try await fetchHTML("/")
        let links = matches(#"<a href="(/serie/[^"]+)" class="home-hero-overlay""#, in: html)
        let imgs = matches(#"(/media/images/backdrop/hero-desktop/[^"\s]+?format=jpg)"#, in: html)
        let alts = matches(#"alt="([^"]+) backdrop""#, in: html)
        var slides: [HeroSlide] = []
        for (i, link) in links.enumerated() where link.count >= 2 {
            let slug = String(link[1].dropFirst("/serie/".count))
            let title = i < alts.count && alts[i].count >= 2 ? decodeEntities(alts[i][1]) : slug
            var backdrop: URL?
            if i < imgs.count && imgs[i].count >= 2 {
                backdrop = absoluteURL(imgs[i][1])
            }
            slides.append(HeroSlide(slug: slug, title: title, backdropURL: backdrop))
        }
        return slides
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
        if detail.coverURL == nil, let img = matches(#"(?:data-src|src)="(/media/images/channel/[^"]+)""#, in: html).first, img.count >= 2 {
            detail.coverURL = absoluteURL(img[1])
        }
        if let img = matches(#"(?:data-src|src)="(/media/images/backdrop/desktop/[^"]+)""#, in: html).first, img.count >= 2 {
            detail.backdropURL = absoluteURL(img[1])
        }
        if detail.backdropURL == nil, let og = matches(#"og:image"\s+content="([^"]+)""#, in: html).first, og.count >= 2 {
            detail.backdropURL = URL(string: og[1])
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

        if let d = matches(#"<(?:div|span|p)[^>]*class="[^"]*description-text[^"]*"[^>]*>([\s\S]*?)</(?:div|span|p)>"#, in: html).first, d.count >= 2 {
            detail.description = decodeEntities(stripTags(d[1])).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if detail.description.isEmpty, let d = matches(#"<div[^>]*class="[^"]*description[^"]*"[^>]*>([\s\S]*?)</div>"#, in: html).first, d.count >= 2 {
            detail.description = decodeEntities(stripTags(d[1])).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if detail.description.isEmpty, let og = matches(#"og:description"\s+content="([^"]+)""#, in: html).first, og.count >= 2 {
            detail.description = decodeEntities(og[1])
        }
        if let imdb = matches(#"imdb\.com/title/(tt\d+)"#, in: html).first, imdb.count >= 2 {
            detail.imdbId = imdb[1]
        }
        if let y = matches(#"href="/jahr/(\d{4})""#, in: html).first, y.count >= 2 {
            detail.year = y[1]
        }
        if let f = matches(#"FSK\s*(\d+)"#, in: html).first, f.count >= 2 {
            detail.fsk = f[1]
        }
        return detail
    }

    // MARK: - Episodes

    func fetchEpisodes(slug: String, season: Int) async throws -> [EpisodeRef] {
        let html = try await fetchHTML("/serie/\(slug)/staffel-\(season)")
        let rows = matches(#"/serie/[^"/]+/staffel-\#(season)/episode-(\d+)"#, in: html)
        var nums = Set<Int>()
        for r in rows where r.count >= 2 {
            if let n = Int(r[1]) { nums.insert(n) }
        }
        // Episodentitel aus der Staffel-Tabelle (episode-row → episode-N + Titel DE/EN)
        var titles: [Int: (String, String?)] = [:]
        let epRows = matches(#"<tr[^>]*class="[^"]*episode-row[^"]*"[^>]*>[\s\S]*?</tr>"#, in: html)
        for row in epRows {
            guard let rowHTML = row.first else { continue }
            guard let numM = matches(#"episode-(\d+)'"#, in: rowHTML).first, numM.count >= 2,
                  let num = Int(numM[1]) else { continue }
            var ger = ""
            var eng: String?
            if let g = matches(#"episode-title-ger[^"]*"[^>]*title="([^"]*)""#, in: rowHTML).first, g.count >= 2 {
                ger = decodeEntities(g[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if ger.isEmpty, let g = matches(#"episode-title-ger[^"]*"[^>]*>([\s\S]*?)</strong>"#, in: rowHTML).first, g.count >= 2 {
                ger = decodeEntities(stripTags(g[1])).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let e = matches(#"episode-title-eng[^"]*"[^>]*title="([^"]*)""#, in: rowHTML).first, e.count >= 2 {
                eng = decodeEntities(e[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !ger.isEmpty { titles[num] = (ger, eng) }
        }
        return nums.sorted().map { n in
            let t = titles[n]
            return EpisodeRef(season: season, episode: n, seriesSlug: slug, title: t?.0, titleEng: t?.1)
        }
    }

    // MARK: - Episode links (Hoster)

    func fetchEpisodeLinks(_ ep: EpisodeRef) async throws -> [EpisodeLink] {
        let html = try await fetchHTML(ep.path)
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
