import Foundation
import SwiftUI

@MainActor
final class CatalogStore: ObservableObject {
    @Published var catalog: [Series] = []
    @Published var popular: [Series] = []
    @Published var catalogLoaded = false
    @Published var loading = false
    @Published var error: String?

    private let client = SerienStreamClient.shared
    private static let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("catalog.json")
    }()

    init() {
        loadCache()
    }

    func loadAll(force: Bool = false) async {
        guard !loading else { return }
        if catalogLoaded && !force { return }
        loading = true
        error = nil
        do {
            async let catalogTask = client.fetchCatalog()
            async let popularTask = client.fetchPopular()
            let (cat, pop) = try await (catalogTask, popularTask)
            catalog = cat
            popular = mergeCovers(popular: pop, catalog: cat)
            catalogLoaded = true
            saveCache()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    /// Cover-URLs aus /beliebte-serien auf Katalog-Einträge übertragen
    private func mergeCovers(popular: [Series], catalog: [Series]) -> [Series] {
        let covers = Dictionary(uniqueKeysWithValues: popular.compactMap { s -> (String, URL)? in
            guard let c = s.coverURL else { return nil }
            return (s.slug, c)
        })
        return popular.map { s in
            var copy = s
            if copy.coverURL == nil { copy.coverURL = covers[s.slug] }
            // Titel aus dem Katalog übernehmen, falls vorhanden
            if let match = catalog.first(where: { $0.slug == s.slug }) {
                copy = Series(slug: s.slug, title: match.title, searchText: match.searchText, coverURL: copy.coverURL)
            }
            return copy
        }
    }

    func coverURL(for slug: String) -> URL? {
        popular.first(where: { $0.slug == slug })?.coverURL
    }

    // MARK: - Cache

    private func saveCache() {
        struct Cache: Codable {
            var catalog: [Series]
            var popular: [Series]
        }
        let cache = Cache(catalog: catalog, popular: popular)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: Self.cacheURL)
        }
    }

    private func loadCache() {
        struct Cache: Codable {
            var catalog: [Series]
            var popular: [Series]
        }
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        catalog = cache.catalog
        popular = cache.popular
        catalogLoaded = !cache.catalog.isEmpty
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
