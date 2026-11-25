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

                    HeroCarousel(catalog: catalog)

                    if !history.recent.isEmpty {
                        continueWatchingSection
                    }

                    NewEpisodesSection()

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


// MARK: - Cinematic Hero Carousel (Apple-TV-Stil) — echte Homepage-Heroes

struct HeroCarousel: View {
    @ObservedObject var catalog: CatalogStore
    @State private var slides: [SerienStreamClient.HeroSlide] = []
    @State private var selection = 0
    @State private var autoAdvanceTask: Task<Void, Never>?

    var body: some View {
        if !slides.isEmpty {
            TabView(selection: $selection) {
                ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                    NavigationLink(value: slide.slug) {
                        HeroCard(slide: slide)
                    }
                    .buttonStyle(.plain)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal)
            .onAppear { startAutoAdvance() }
            .onDisappear { autoAdvanceTask?.cancel() }
        } else {
            Color.clear.frame(height: 0)
                .task { await load() }
        }
    }

    private func load() async {
        if let heroes = try? await SerienStreamClient.shared.fetchHomeHeroes(), !heroes.isEmpty {
            await MainActor.run { slides = heroes }
        }
    }

    private func startAutoAdvance() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, !slides.isEmpty else { return }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        selection = (selection + 1) % slides.count
                    }
                }
            }
        }
    }
}

struct HeroCard: View {
    let slide: SerienStreamClient.HeroSlide

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: slide.backdropURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .empty:
                    DS.bgElevated.overlay(ProgressView().tint(DS.textTertiary))
                default:
                    DS.bgElevated
                }
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.55), .black.opacity(0.9)],
                startPoint: UnitPoint(x: 0.5, y: 0.25),
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                Spacer()
                Text(slide.title)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.7), radius: 8, y: 2)
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Jetzt ansehen")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
    }
}


// MARK: - Neue Episoden (Kalender)

struct NewEpisodesSection: View {
    @State private var episodes: [SerienStreamClient.CalendarEpisode] = []
    @State private var loaded = false

    private var shown: [SerienStreamClient.CalendarEpisode] {
        // Nur veröffentlichte, dedupliziert pro Serie (neueste Episode zuerst)
        var seen = Set<String>()
        var out: [SerienStreamClient.CalendarEpisode] = []
        for ep in episodes where ep.released {
            if seen.contains(ep.seriesSlug) { continue }
            seen.insert(ep.seriesSlug)
            out.append(ep)
            if out.count >= 15 { break }
        }
        return out
    }

    var body: some View {
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Neue Episoden")
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(shown) { ep in
                            NavigationLink(value: ep.seriesSlug) {
                                NewEpisodeCard(episode: ep)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        } else if !loaded {
            Color.clear.frame(height: 0)
                .task {
                    episodes = (try? await SerienStreamClient.shared.fetchCalendar()) ?? []
                    loaded = true
                }
        }
    }
}

struct NewEpisodeCard: View {
    let episode: SerienStreamClient.CalendarEpisode

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: episode.date) else { return episode.date }
        let out = DateFormatter()
        out.locale = Locale(identifier: "de_DE")
        out.dateFormat = "EEE, d. MMM"
        return out.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                CoverImage(url: episode.coverURL)
                    .frame(width: 120, height: 172)
                Text("S\(episode.season) E\(episode.episode)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(7)
            }
            .frame(width: 120, height: 172)
            Text(episode.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.textPrimary)
                .lineLimit(1)
            Text(dateLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.textTertiary)
        }
        .frame(width: 120, alignment: .leading)
    }
}
