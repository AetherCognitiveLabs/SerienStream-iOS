import SwiftUI

@main
struct SerienStreamApp: App {
    @StateObject private var catalog = CatalogStore()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var history = WatchHistoryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(catalog)
                .environmentObject(favorites)
                .environmentObject(history)
                .preferredColorScheme(.dark)
                .task {
                    await catalog.loadAll()
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var favorites: FavoritesStore

    var body: some View {
        TabView {
            HomeView(catalog: catalog)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            SeriesListView(catalog: catalog)
                .tabItem {
                    Label("Serien", systemImage: "tv.fill")
                }
            FavoritesView(catalog: catalog)
                .tabItem {
                    Label("Favoriten", systemImage: "heart.fill")
                }
            SettingsView()
                .tabItem {
                    Label("Mehr", systemImage: "ellipsis")
                }
        }
        .tint(DS.accent)
    }
}

struct FavoritesView: View {
    @ObservedObject var catalog: CatalogStore
    @EnvironmentObject private var favorites: FavoritesStore

    private var favoriteSeries: [Series] {
        catalog.catalog.filter { favorites.isFavorite($0.slug) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if favoriteSeries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "heart")
                            .font(.system(size: 44, weight: .light))
                            .foregroundColor(DS.textTertiary)
                        Text("Keine Favoriten")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(DS.textSecondary)
                        Text("Markiere Serien mit dem Herz, um sie hier zu sehen.")
                            .font(.footnote)
                            .foregroundColor(DS.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(favoriteSeries) { series in
                                NavigationLink(value: series.slug) {
                                    SeriesRow(series: series, coverURL: catalog.coverURL(for: series.slug))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle("Favoriten")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: String.self) { slug in
                SeriesDetailView(slug: slug)
            }
        }
    }
}
