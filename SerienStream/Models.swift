import Foundation

struct Series: Identifiable, Hashable, Codable {
    var id: String { slug }
    let slug: String
    let title: String
    let searchText: String
    var coverURL: URL?
}

struct SeriesDetail {
    let slug: String
    let title: String
    var description: String
    var genres: [String]
    var coverURL: URL?
    var backdropURL: URL?
    var seasons: [Int]
}

struct EpisodeRef: Identifiable, Hashable {
    var id: String { "\(season)/\(episode)" }
    let season: Int
    let episode: Int
    let seriesSlug: String
    var title: String?

    var path: String { "/serie/\(seriesSlug)/staffel-\(season)/episode-\(episode)" }
}

struct EpisodeLink: Identifiable, Hashable {
    var id: String { linkId }
    let linkId: String
    let providerName: String
    let languageLabel: String
    let playPath: String // /r?t=TOKEN
}

struct StreamResult {
    let streamURL: URL
    let headers: [String: String]
}

enum AppError: LocalizedError {
    case network(String)
    case parsing(String)
    case resolutionFailed(String)
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .network(let m): return "Netzwerkfehler: \(m)"
        case .parsing(let m): return "Lesefehler: \(m)"
        case .resolutionFailed(let m): return m
        case .extractionFailed(let m): return m
        }
    }
}
