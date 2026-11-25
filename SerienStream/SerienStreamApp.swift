import SwiftUI

@main
struct SerienStreamApp: App {
    @StateObject private var catalog = CatalogStore()
    @StateObject private var favorites = FavoritesStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(catalog)
                .environmentObject(favorites)
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

struct SettingsView: View {
    @AppStorage("serienstream.domain") private var domain = "https://serienstream.to"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Domain")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(DS.textPrimary)
                        Text("Falls eine Domain gesperrt ist, wechsle auf eine Alternative.")
                            .font(.footnote)
                            .foregroundColor(DS.textSecondary)
                        ForEach(SerienStreamClient.domains, id: \.self) { d in
                            Button {
                                domain = d
                            } label: {
                                HStack {
                                    Image(systemName: domain == d ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(domain == d ? DS.accent : DS.textTertiary)
                                    Text(d)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(DS.textPrimary)
                                    Spacer()
                                }
                                .padding(12)
                                .glass()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)

                    Text("Version 1.0 — Inoffizielle SerienStream-App. Alle Inhalte stammen von serienstream.to.")
                        .font(.caption)
                        .foregroundColor(DS.textTertiary)
                        .padding(.horizontal)
                }
                .padding(.top, 16)
            }
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle("Einstellungen")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
