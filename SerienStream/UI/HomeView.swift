import SwiftUI

struct HomeView: View {
    @ObservedObject var catalog: CatalogStore
    @EnvironmentObject private var history: WatchHistoryStore
    @EnvironmentObject private var favorites: FavoritesStore

    struct GenreItem: Identifiable { let id: String; let label: String }
    let genres: [GenreItem] = [
        GenreItem(id: "action", label: "Action"), GenreItem(id: "animation", label: "Animation"), GenreItem(id: "anime", label: "Anime"),
        GenreItem(id: "comedy", label: "Comedy"), GenreItem(id: "drama", label: "Drama"), GenreItem(id: "fantasy", label: "Fantasy"),
        GenreItem(id: "horror", label: "Horror"), GenreItem(id: "krimi", label: "Krimi"), GenreItem(id: "sci-fi", label: "Sci-Fi"),
        GenreItem(id: "thriller", label: "Thriller"), GenreItem(id: "dokumentation", label: "Doku"), GenreItem(id: "familie", label: "Familie")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if let error = catalog.error {
                        errorBanner(error)
                    }

                    if !history.recent.isEmpty {
                        continueWatchingSection
                    }

                    favoritesSection

                    genreChips

                    if catalog.sections.isEmpty && catalog.loading {
                        ProgressView().tint(DS.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        ForEach(catalog.sections, id: \.title) { section in
                            sectionRow(section)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle("SerienStream")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: String.self) { route in
                if route.hasPrefix("genre:") {
                    GenreView(genre: String(route.dropFirst(6)))
                } else {
                    SeriesDetailView(slug: route)
                }
            }
            .refreshable {
                await catalog.loadAll(force: true)
            }
        }
    }

    // MARK: - Continue Watching

    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Weiterschauen")
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(history.recent.prefix(12).map { $0 }) { entry in
                        NavigationLink(value: entry.seriesSlug) {
                            ContinueCard(entry: entry, coverURL: catalog.coverURL(for: entry.seriesSlug))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Favoriten

    @ViewBuilder
    private var favoritesSection: some View {
        let favSeries = catalog.catalog.filter { favorites.isFavorite($0.slug) }
        if !favSeries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Meine Favoriten")
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(favSeries) { series in
                            NavigationLink(value: series.slug) {
                                CoverCard(series: seriesWithCover(series))
                                    .frame(width: 110)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func seriesWithCover(_ series: Series) -> Series {
        if series.coverURL != nil { return series }
        var copy = series
        copy.coverURL = catalog.coverURL(for: series.slug)
        if copy.coverURL == nil { catalog.loadCoverIfNeeded(for: series.slug) }
        return copy
    }

    // MARK: - Sections

    private func sectionRow(_ section: SerienStreamClient.PopularSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: section.title)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(section.series) { series in
                        NavigationLink(value: series.slug) {
                            CoverCard(series: series)
                                .frame(width: 110)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.footnote)
                .foregroundColor(DS.textSecondary)
            Spacer()
        }
        .padding(12)
        .glass()
        .padding(.horizontal)
    }

    private var genreChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(genres) { genre in
                    NavigationLink(value: "genre:\(genre.id)") {
                        Text(genre.label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .glass()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

struct ContinueCard: View {
    let entry: WatchEntry
    let coverURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                CoverImage(url: coverURL)
                    .frame(width: 150, height: 96)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous)
                            .fill(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom))
                    )
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("S\(entry.season) · E\(entry.episode)")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DS.accent.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(8)
            }
            .frame(width: 150, height: 96)
            ProgressBar(entry: entry)
            Text(entry.seriesTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.textPrimary)
                .lineLimit(1)
        }
        .frame(width: 150, alignment: .leading)
    }
}

struct CoverCard: View {
    let series: Series

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverImage(url: series.coverURL)
                .aspectRatio(2/3, contentMode: .fit)
                .frame(maxWidth: .infinity)
            Text(series.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }
}


struct ProgressBar: View {
    let entry: WatchEntry
    @EnvironmentObject private var history: WatchHistoryStore

    var body: some View {
        let prog = history.progress(seriesSlug: entry.seriesSlug, season: entry.season, episode: entry.episode)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                if prog > 0 {
                    Capsule().fill(DS.accent)
                        .frame(width: geo.size.width * prog)
                }
            }
        }
        .frame(width: 150, height: 3)
        .opacity(prog > 0.01 ? 1 : 0)
    }
}
