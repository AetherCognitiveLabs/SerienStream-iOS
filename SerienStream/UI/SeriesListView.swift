import SwiftUI

struct SeriesListView: View {
    @ObservedObject var catalog: CatalogStore
    @State private var search = ""
    @State private var path = NavigationPath()

    private var filtered: [Series] {
        if search.isEmpty { return catalog.catalog }
        let q = search.lowercased()
        return catalog.catalog.filter { $0.searchText.contains(q) || $0.title.lowercased().contains(q) }
    }

    private var grouped: [(letter: String, items: [Series])] {
        let groups = Dictionary(grouping: filtered) { series -> String in
            let first = series.title.first ?? "#"
            return first.isLetter ? String(first).uppercased() : "#"
        }
        return groups.keys.sorted().map { (letter: $0, items: groups[$0]!.sorted { $0.title < $1.title }) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(grouped, id: \.letter) { group in
                        Section {
                            ForEach(group.items) { series in
                                NavigationLink(value: series.slug) {
                                    SeriesRow(series: series, coverURL: catalog.coverURL(for: series.slug))
                                }
                                .buttonStyle(.plain)
                                .onAppear {
                                    catalog.loadCoverIfNeeded(for: series.slug)
                                }
                            }
                        } header: {
                            Text(group.letter)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(DS.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.vertical, 6)
                                .background(DS.bg)
                        }
                    }
                }
            }
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle("Alle Serien")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if let random = catalog.catalog.randomElement() {
                            path.append(random.slug)
                        }
                    } label: {
                        Image(systemName: "shuffle")
                            .foregroundColor(DS.accent)
                    }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(text: $search, prompt: "Serie suchen…")
            .navigationDestination(for: String.self) { route in
                if route.hasPrefix("genre:") {
                    GenreView(genre: String(route.dropFirst(6)))
                } else {
                    SeriesDetailView(slug: route)
                }
            }
            .overlay {
                if catalog.catalog.isEmpty && catalog.loading {
                    ProgressView().tint(DS.accent)
                }
            }
        }
    }
}

struct SeriesRow: View {
    let series: Series
    let coverURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(url: coverURL, cornerRadius: 8)
                .frame(width: 44, height: 62)
            Text(series.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(DS.textPrimary)
                .lineLimit(2)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.textTertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}

struct GenreView: View {
    let genre: String
    @State private var series: [Series] = []
    @State private var loading = true
    @State private var error: String?

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            if loading {
                ProgressView().tint(DS.accent).padding(.top, 60)
            } else if let error {
                Text(error).foregroundColor(DS.textSecondary).padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(series) { s in
                        NavigationLink(value: s.slug) {
                            CoverCard(series: s)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .background(DS.bg.ignoresSafeArea())
        .navigationTitle(genre.capitalized)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(for: String.self) { slug in
            SeriesDetailView(slug: slug)
        }
        .task {
            do {
                series = try await SerienStreamClient.shared.fetchGenre(genre)
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}
