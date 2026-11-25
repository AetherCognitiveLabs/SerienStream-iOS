import SwiftUI

struct SeriesDetailView: View {
    let slug: String

    @State private var detail: SeriesDetail?
    @State private var episodes: [EpisodeRef] = []
    @State private var selectedSeason: Int?
    @State private var loadingDetail = true
    @State private var loadingEpisodes = false
    @State private var error: String?
    @State private var playingEpisode: EpisodeRef?
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var history: WatchHistoryStore

    private let client = SerienStreamClient.shared

    var body: some View {
        ScrollView {
            if loadingDetail {
                ProgressView().tint(DS.accent).padding(.top, 80)
            } else if let detail {
                VStack(alignment: .leading, spacing: 0) {
                    hero(detail)
                    content(detail)
                }
            } else {
                Text(error ?? "Nicht gefunden")
                    .foregroundColor(DS.textSecondary)
                    .padding(.top, 80)
            }
        }
        .background(DS.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    favorites.toggle(slug)
                } label: {
                    Image(systemName: favorites.isFavorite(slug) ? "heart.fill" : "heart")
                        .foregroundColor(favorites.isFavorite(slug) ? .red : DS.textPrimary)
                }
            }
        }
        .fullScreenCover(item: $playingEpisode) { ep in
            PlaybackFlowView(episode: ep, seriesTitle: detail?.title ?? "", seasonEpisodes: episodes)
        }
        .task {
            do {
                let d = try await client.fetchDetail(slug: slug)
                detail = d
                if let first = d.seasons.first {
                    selectedSeason = first
                }
                // TMDB-Anreicherung (Score, Logo, HD-Backdrop) — nur wenn Key hinterlegt
                if TMDBClient.shared.isConfigured, var enriched = detail {
                    if let tmdb = await TMDBClient.shared.enrich(title: d.title, imdbId: d.imdbId, cacheKey: slug) {
                        enriched.tmdbScore = tmdb.score
                        enriched.tmdbLogoURL = tmdb.logoURL
                        enriched.tmdbBackdropURL = tmdb.backdropURL
                        detail = enriched
                    }
                }
            } catch {
                self.error = error.localizedDescription
            }
            loadingDetail = false
        }
        .onChange(of: selectedSeason) { season in
            guard let season else { return }
            loadEpisodes(season: season)
        }
    }

    private func loadEpisodes(season: Int) {
        loadingEpisodes = true
        Task {
            do {
                episodes = try await client.fetchEpisodes(slug: slug, season: season)
            } catch {
                episodes = []
            }
            loadingEpisodes = false
        }
    }

    // MARK: - Hero

    private func hero(_ detail: SeriesDetail) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: detail.tmdbBackdropURL ?? detail.backdropURL ?? detail.coverURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    DS.bgElevated
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width)
            .frame(height: 340)
            .clipped()
            .overlay(
                LinearGradient(
                    colors: [.clear, DS.bg.opacity(0.55), DS.bg],
                    startPoint: UnitPoint(x: 0.5, y: 0.2),
                    endPoint: .bottom
                )
            )

            VStack(alignment: .leading, spacing: 10) {
                Spacer()
                if let logoURL = detail.tmdbLogoURL {
                    AsyncImage(url: logoURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 220, maxHeight: 80, alignment: .leading)
                        } else {
                            titleText(detail)
                        }
                    }
                    .frame(maxWidth: 220, alignment: .leading)
                } else {
                    titleText(detail)
                }

                // Badge-Zeile: Score, Jahr, FSK, Genres
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let score = detail.tmdbScore {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.yellow)
                                Text(String(format: "%.1f", score))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        if let year = detail.year {
                            metaBadge(year)
                        }
                        if let fsk = detail.fsk {
                            metaBadge("FSK \(fsk)")
                        }
                        ForEach(detail.genres.prefix(3), id: \.self) { g in
                            metaBadge(g.capitalized)
                        }
                        if detail.imdbId != nil {
                            metaBadge("IMDb")
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 14)
        }
        .frame(height: 340)
    }

    private func titleText(_ detail: SeriesDetail) -> some View {
        Text(detail.title)
            .font(.system(size: 26, weight: .heavy, design: .rounded))
            .foregroundColor(DS.textPrimary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: .black.opacity(0.6), radius: 8, y: 2)
    }

    private func metaBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Content

    private func content(_ detail: SeriesDetail) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let next = nextUnwatchedEpisode() {
                Button {
                    playingEpisode = next
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("Weiterschauen: S\(next.season) E\(next.episode)\(next.title.map { " — \($0)" } ?? "")")
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .background(DS.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal)
                }
                .buttonStyle(.plain)
            }

            if !detail.description.isEmpty {
                Text(detail.description)
                    .font(.system(size: 14))
                    .foregroundColor(DS.textSecondary)
                    .lineSpacing(4)
                    .padding(.horizontal)
            }

            if detail.seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(detail.seasons, id: \.self) { season in
                            Button {
                                selectedSeason = season
                            } label: {
                                Text("Staffel \(season)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(selectedSeason == season ? .black : DS.textPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(selectedSeason == season ? DS.accent : Color.clear)
                                    )
                                    .glass(radius: 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }

            episodeList
        }
        .padding(.top, 16)
        .padding(.bottom, 40)
    }

    /// Erste Episode der aktuellen Staffel mit gespeicherter Position oder erste ungesehene.
    private func nextUnwatchedEpisode() -> EpisodeRef? {
        guard !episodes.isEmpty else { return nil }
        if let inProgress = episodes.first(where: { history.progress(seriesSlug: slug, season: $0.season, episode: $0.episode) > 0.01 }) {
            return inProgress
        }
        if let unwatched = episodes.first(where: { !history.isWatched(seriesSlug: slug, season: $0.season, episode: $0.episode) }) {
            return unwatched
        }
        return nil
    }

    private var episodeList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let season = selectedSeason {
                Text("Episoden — Staffel \(season)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(DS.textPrimary)
                    .padding(.horizontal)
            }

            if loadingEpisodes {
                ProgressView().tint(DS.accent)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if episodes.isEmpty {
                Text("Keine Episoden gefunden")
                    .font(.footnote)
                    .foregroundColor(DS.textTertiary)
                    .padding(.horizontal)
            } else {
                ForEach(episodes) { ep in
                    Button {
                        playingEpisode = ep
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 14) {
                                Text("\(ep.episode)")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(DS.accent)
                                    .frame(width: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ep.title ?? "Episode \(ep.episode)")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(DS.textPrimary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    if let eng = ep.titleEng, eng != ep.title {
                                        Text(eng)
                                            .font(.system(size: 12))
                                            .foregroundColor(DS.textTertiary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                if history.isWatched(seriesSlug: slug, season: ep.season, episode: ep.episode) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.green)
                                }
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(DS.accent)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)

                            let prog = history.progress(seriesSlug: slug, season: ep.season, episode: ep.episode)
                            if prog > 0.01 {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.white.opacity(0.15))
                                        Capsule().fill(DS.accent)
                                            .frame(width: geo.size.width * prog)
                                    }
                                }
                                .frame(height: 3)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 8)
                            }
                        }
                        .glass(radius: 14)
                        .padding(.horizontal)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            history.toggleWatched(seriesSlug: slug, seriesTitle: detail?.title ?? slug, season: ep.season, episode: ep.episode)
                        } label: {
                            if history.isWatched(seriesSlug: slug, season: ep.season, episode: ep.episode) {
                                Label("Als ungesehen markieren", systemImage: "eye.slash")
                            } else {
                                Label("Als gesehen markieren", systemImage: "eye")
                            }
                        }
                    }
                }
            }
        }
    }
}
