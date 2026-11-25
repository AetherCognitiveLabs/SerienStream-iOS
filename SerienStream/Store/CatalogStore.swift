import Foundation
import SwiftUI

@MainActor
final class CatalogStore: ObservableObject {
    @Published var catalog: [Series] = []
    @Published var sections: [SerienStreamClient.PopularSection] = []
    @Published var catalogLoaded = false
    @Published var loading = false
    @Published var error: String?
    @Published var activeEndpoint: String = ""
    @Published var coverCache: [String: URL] = [:]

    private let client = SerienStreamClient.shared
    private var coverInflight = Set<String>()

    private static let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("catalog_v2.json")
    }()

    init() {
        activeEndpoint = client.baseURL
        loadCache()
    }

    func loadAll(force: Bool = false) async {
        guard !loading else { return }
        if catalogLoaded && !force { return }
        loading = true
        error = nil
        if force || catalog.isEmpty {
            activeEndpoint = await client.autoSelectEndpoint()
        }
        do {
            async let catalogTask = client.fetchCatalog()
            async let sectionsTask = client.fetchPopularSections()
            let cat = try await catalogTask
            let sec = (try? await sectionsTask) ?? []
            catalog = cat
            sections = enrichTitles(sections: sec, catalog: cat)
            cacheCoversFromSections()
            catalogLoaded = true
            saveCache()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func enrichTitles(sections: [SerienStreamClient.PopularSection], catalog: [Series]) -> [SerienStreamClient.PopularSection] {
        let titleMap = Dictionary(uniqueKeysWithValues: catalog.map { ($0.slug, $0.title) })
        return sections.map { section in
            var copy = section
            copy.series = section.series.map { s in
                guard let realTitle = titleMap[s.slug] else { return s }
                return Series(slug: s.slug, title: realTitle, searchText: realTitle.lowercased(), coverURL: s.coverURL)
            }
            return copy
        }
    }

    private func cacheCoversFromSections() {
        for section in sections {
            for s in section.series {
                if let cover = s.coverURL { coverCache[s.slug] = cover }
            }
        }
    }

    func coverURL(for slug: String) -> URL? {
        coverCache[slug]
    }

    /// Lädt das Cover einer Serie lazy über die Detailseite (für Listen ohne Cover).
    func loadCoverIfNeeded(for slug: String) {
        guard coverCache[slug] == nil, !coverInflight.contains(slug) else { return }
        coverInflight.insert(slug)
        Task {
            defer { coverInflight.remove(slug) }
            if let detail = try? await client.fetchDetail(slug: slug), let cover = detail.coverURL {
                coverCache[slug] = cover
            }
        }
    }

    // MARK: - Cache

    private struct Cache: Codable {
        var catalog: [Series]
        var covers: [String: URL]
    }

    private func saveCache() {
        let cache = Cache(catalog: catalog, covers: coverCache)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: Self.cacheURL)
        }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        catalog = cache.catalog
        coverCache = cache.covers
        catalogLoaded = !cache.catalog.isEmpty
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: Self.cacheURL)
        catalog = []
        sections = []
        coverCache = [:]
        catalogLoaded = false
    }
}

@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var slugs: Set<String> = []

    private static let key = "serienstream.favorites"

    init() {
        if let arr = UserDefaults.standard.array(forKey: Self.key) as? [String] {
            slugs = Set(arr)
        }
    }

    func toggle(_ slug: String) {
        if slugs.contains(slug) { slugs.remove(slug) } else { slugs.insert(slug) }
        UserDefaults.standard.set(Array(slugs), forKey: Self.key)
    }

    func isFavorite(_ slug: String) -> Bool {
        slugs.contains(slug)
    }
}

struct WatchEntry: Codable, Identifiable {
    var id: String { "\(seriesSlug)-s\(season)e\(episode)" }
    let seriesSlug: String
    let seriesTitle: String
    let season: Int
    let episode: Int
    var date: Date
}

@MainActor
final class WatchHistoryStore: ObservableObject {
    /// Zuletzt gespielte Episoden, neueste zuerst
    @Published private(set) var recent: [WatchEntry] = []
    /// Als gesehen markierte Episoden-IDs
    @Published private(set) var watched: Set<String> = []

    private static let recentKey = "serienstream.history"
    private static let watchedKey = "serienstream.watched"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.recentKey),
           let entries = try? JSONDecoder().decode([WatchEntry].self, from: data) {
            recent = entries
        }
        if let arr = UserDefaults.standard.array(forKey: Self.watchedKey) as? [String] {
            watched = Set(arr)
        }
    }

    func markPlayed(seriesSlug: String, seriesTitle: String, season: Int, episode: Int) {
        let entry = WatchEntry(seriesSlug: seriesSlug, seriesTitle: seriesTitle, season: season, episode: episode, date: Date())
        recent.removeAll { $0.id == entry.id }
        recent.insert(entry, at: 0)
        if recent.count > 50 { recent = Array(recent.prefix(50)) }
        watched.insert(entry.id)
        persist()
    }

    func isWatched(seriesSlug: String, season: Int, episode: Int) -> Bool {
        watched.contains("\(seriesSlug)-s\(season)e\(episode)")
    }

    func toggleWatched(seriesSlug: String, seriesTitle: String, season: Int, episode: Int) {
        let id = "\(seriesSlug)-s\(season)e\(episode)"
        if watched.contains(id) {
            watched.remove(id)
        } else {
            watched.insert(id)
            markPlayed(seriesSlug: seriesSlug, seriesTitle: seriesTitle, season: season, episode: episode)
        }
        persist()
    }

    func clear() {
        recent = []
        watched = []
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(recent) {
            UserDefaults.standard.set(data, forKey: Self.recentKey)
        }
        UserDefaults.standard.set(Array(watched), forKey: Self.watchedKey)
    }
}
