import SwiftUI

struct HomeView: View {
    @ObservedObject var catalog: CatalogStore
    let genres: [(name: String, label: String)] = [
        ("action", "Action"), ("animation", "Animation"), ("anime", "Anime"),
        ("comedy", "Comedy"), ("drama", "Drama"), ("fantasy", "Fantasy"),
        ("horror", "Horror"), ("krimi", "Krimi"), ("sci-fi", "Sci-Fi"),
        ("thriller", "Thriller"), ("dokumentation", "Doku"), ("familie", "Familie")
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let error = catalog.error {
                        errorBanner(error)
                    }

                    SectionHeader(title: "Beliebte Serien")
                        .padding(.horizontal)

                    if catalog.popular.isEmpty && catalog.loading {
                        ProgressView().tint(DS.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(catalog.popular) { series in
                                NavigationLink(value: series.slug) {
                                    CoverCard(series: series)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }

                    SectionHeader(title: "Genres")
                        .padding(.horizontal)
                    genreChips
                        .padding(.bottom, 32)
                }
                .padding(.top, 12)
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

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.footnote)
                .foregroundColor(DS.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
        .padding(.horizontal)
    }

    private var genreChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(genres, id: \.name) { genre in
                    NavigationLink(value: "genre:\(genre.name)") {
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

struct CoverCard: View {
    let series: Series

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverImage(url: series.coverURL)
                .aspectRatio(2/3, contentMode: .fit)
            Text(series.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }
}
