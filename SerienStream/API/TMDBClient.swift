import Foundation

/// TMDB-Anbindung für Scores, Backdrops in HD, Logos und Metadaten.
/// Der Nutzer hinterlegt seinen kostenlosen API-Key in den Einstellungen
/// (anlegen in 2 Minuten unter themoviedb.org/settings/api).
final class TMDBClient {
    static let shared = TMDBClient()

    static let keyDefaultsKey = "serienstream.tmdbKey"

    var apiKey: String {
        get { UserDefaults.standard.string(forKey: Self.keyDefaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.keyDefaultsKey) }
    }

    var isConfigured: Bool { !apiKey.isEmpty }

    struct TMDBResult {
        var score: Double?          // 0…10
        var voteCount: Int?
        var backdropURL: URL?       // HD-Backdrop
        var logoURL: URL?           // Serienlogo (transparent, falls vorhanden)
        var posterURL: URL?         // HD-Poster
        var overview: String?
        var year: String?
        var tmdbId: Int?
    }

    private var cache: [String: TMDBResult] = [:]
    private var inflight: [String: Task<TMDBResult?, Never>] = [:]

    private let session = URLSession(configuration: {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 12
        return c
    }())

    private func get(_ path: String, query: [String: String]) async -> [String: Any]? {
        guard isConfigured else { return nil }
        var comps = URLComponents(string: "https://api.themoviedb.org/3" + path)
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "api_key", value: apiKey))
        comps?.queryItems = items
        guard let url = comps?.url else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    private func imageURL(_ path: Any?, size: String) -> URL? {
        guard let p = path as? String, !p.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(p)")
    }

    /// Sucht die Serie bei TMDB — bevorzugt über die IMDb-ID (eindeutig), sonst per Titelsuche.
    func enrich(title: String, imdbId: String?, cacheKey: String) async -> TMDBResult? {
        guard isConfigured else { return nil }
        if let hit = cache[cacheKey] { return hit }
        if let task = inflight[cacheKey] { return await task.value }

        let task = Task<TMDBResult?, Never> {
            var result = TMDBResult()
            var seriesId: Int?

            if let imdbId {
                if let json = await get("/find/\(imdbId)", query: ["external_source": "imdb_id"]),
                   let tvResults = json["tv_results"] as? [[String: Any]],
                   let first = tvResults.first,
                   let id = first["id"] as? Int {
                    seriesId = id
                }
            }
            if seriesId == nil {
                if let json = await get("/search/tv", query: ["query": title, "language": "de-DE"]),
                   let results = json["results"] as? [[String: Any]],
                   let first = results.first,
                   let id = first["id"] as? Int {
                    seriesId = id
                }
            }
            guard let id = seriesId else {
                await MainActor.run { self.inflight[cacheKey] = nil }
                return nil
            }
            result.tmdbId = id

            if let details = await get("/tv/\(id)", query: ["language": "de-DE", "append_to_response": "images", "include_image_language": "de,en,null"]) {
                if let score = details["vote_average"] as? Double, score > 0 {
                    result.score = score
                }
                result.voteCount = details["vote_count"] as? Int
                result.backdropURL = imageURL(details["backdrop_path"], size: "w1280")
                result.posterURL = imageURL(details["poster_path"], size: "w500")
                result.overview = details["overview"] as? String
                if let air = details["first_air_date"] as? String, air.count >= 4 {
                    result.year = String(air.prefix(4))
                }
                // Logo: bevorzugt deutsch, dann englisch, dann irgendeins
                if let images = details["images"] as? [String: Any],
                   let logos = images["logos"] as? [[String: Any]], !logos.isEmpty {
                    let sorted = logos.sorted { a, b in
                        let la = (a["iso_639_1"] as? String) ?? "zz"
                        let lb = (b["iso_639_1"] as? String) ?? "zz"
                        let ra = la == "de" ? 0 : (la == "en" ? 1 : 2)
                        let rb = lb == "de" ? 0 : (lb == "en" ? 1 : 2)
                        return ra < rb
                    }
                    result.logoURL = imageURL(sorted.first?["file_path"], size: "w500")
                }
            }
            await MainActor.run {
                self.cache[cacheKey] = result
                self.inflight[cacheKey] = nil
            }
            return result
        }
        inflight[cacheKey] = task
        return await task.value
    }
}
