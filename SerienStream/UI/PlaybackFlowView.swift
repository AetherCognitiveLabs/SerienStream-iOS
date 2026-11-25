import SwiftUI
import WebKit

struct WebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Steuert den kompletten Wiedergabe-Flow: Hoster wählen → Gate lösen → Stream extrahieren → abspielen
struct PlaybackFlowView: View {
    let episode: EpisodeRef
    let seriesTitle: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var history: WatchHistoryStore
    @StateObject private var resolver = StreamResolver()

    @State private var links: [EpisodeLink] = []
    @State private var loadingLinks = true
    @State private var linksError: String?

    @State private var phase: Phase = .hosterSelection
    @State private var stream: StreamResult?
    @State private var embedFallbackURL: URL?
    @State private var errorMessage: String?

    enum Phase {
        case hosterSelection
        case resolving
        case playing
        case webViewFallback
        case failed
    }

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
        .task {
            do {
                links = try await SerienStreamClient.shared.fetchEpisodeLinks(episode)
                DLog("Hoster gefunden: \(links.map { $0.providerName }.joined(separator: ", "))", category: "player")
                if links.isEmpty {
                    linksError = "Keine Hoster gefunden"
                    DLog("Keine Hoster auf \(episode.path)", category: "player")
                }
            } catch {
                linksError = error.localizedDescription
                DLog("Hoster-Fehler: \(error.localizedDescription)", category: "player")
            }
            loadingLinks = false
            if CommandLine.arguments.contains("-smokeResolver"), let first = links.first {
                DLog("SmokeResolver: starte automatisch mit \(first.providerName)", category: "smoke")
                startResolution(first)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .hosterSelection:
            hosterSelection
        case .resolving:
            resolvingView
        case .playing:
            if let stream {
                PlayerScreen(stream: stream, title: title)
            }
        case .webViewFallback:
            if let url = embedFallbackURL {
                EmbedPlayerView(embedURL: url, title: title) {
                    dismiss()
                }
            }
        case .failed:
            failedView
        }
    }

    private var title: String {
        "\(seriesTitle) — S\(episode.season) E\(episode.episode)"
    }

    // MARK: - Hoster-Auswahl

    private var hosterSelection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(DS.textPrimary)
                    Text("Hoster wählen")
                        .font(.system(size: 13))
                        .foregroundColor(DS.textSecondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DS.textSecondary)
                        .padding(10)
                        .glass(radius: 10)
                }
                .buttonStyle(.plain)
            }
            .padding()

            if loadingLinks {
                ProgressView().tint(DS.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let linksError {
                Text(linksError)
                    .foregroundColor(DS.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    let languages = Dictionary(grouping: links, by: { $0.languageLabel })
                    ForEach(languages.keys.sorted(), id: \.self) { lang in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(lang)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(DS.accent)
                                .padding(.horizontal)
                            ForEach(languages[lang] ?? []) { link in
                                Button {
                                    startResolution(link)
                                } label: {
                                    HStack {
                                        Image(systemName: "play.rectangle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(DS.accent)
                                        Text(link.providerName)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(DS.textPrimary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(DS.textTertiary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .glass()
                                    .padding(.horizontal)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    // MARK: - Resolver

    private func startResolution(_ link: EpisodeLink) {
        phase = .resolving
        errorMessage = nil
        Task {
            do {
                let embedURL = try await resolver.resolve(
                    episodePath: episode.path,
                    link: link,
                    baseURL: SerienStreamClient.shared.baseURL
                )
                // Embed gefunden → in derselben WebView laden und Stream-Netzwerkverkehr scannen
                DLog("Embed gefunden: \(embedURL.absoluteString) — lade zur Extraktion", category: "player")
                var result: StreamResult?
                if let webView = resolver.webView {
                    var request = URLRequest(url: embedURL)
                    request.setValue(SerienStreamClient.shared.baseURL + "/", forHTTPHeaderField: "Referer")
                    request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
                    await MainActor.run { webView.load(request) }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    result = await WebViewStreamExtractor.scan(in: webView, embedURL: embedURL)
                }
                if let result {
                    DLog("Stream gefunden: \(result.streamURL.absoluteString)", category: "player")
                    stream = result
                    history.markPlayed(seriesSlug: episode.seriesSlug, seriesTitle: seriesTitle, season: episode.season, episode: episode.episode)
                    phase = .playing
                } else {
                    // Klassische HTML-Extraktion als zweiter Versuch
                    if let classic = try? await HosterExtractor.shared.extract(embedURL: embedURL) {
                        DLog("Stream klassisch gefunden: \(classic.streamURL.absoluteString)", category: "player")
                        stream = classic
                        history.markPlayed(seriesSlug: episode.seriesSlug, seriesTitle: seriesTitle, season: episode.season, episode: episode.episode)
                        phase = .playing
                    } else {
                        DLog("Extraktion fehlgeschlagen — WebView-Fallback", category: "player")
                        embedFallbackURL = embedURL
                        history.markPlayed(seriesSlug: episode.seriesSlug, seriesTitle: seriesTitle, season: episode.season, episode: episode.episode)
                        phase = .webViewFallback
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
                phase = .failed
            }
        }
    }

    private var resolvingView: some View {
        ZStack(alignment: .top) {
            if let webView = resolver.webView {
                WebViewRepresentable(webView: webView)
                    .ignoresSafeArea()
            }

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusText)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(DS.textPrimary)
                        Text("Tippe ggf. das Kontrollkästchen an und drücke „Weiter“")
                            .font(.system(size: 11))
                            .foregroundColor(DS.textSecondary)
                    }
                    Spacer()
                    Button {
                        resolver.cancel()
                        phase = .hosterSelection
                    } label: {
                        Text("Abbrechen")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DS.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glass(radius: 10)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(DS.bg.opacity(0.9))

                Spacer()
            }
        }
    }

    private var statusText: String {
        switch resolver.state {
        case .loadingPage: return "Lade Episodenseite…"
        case .waitingForGate: return "Sicherheitsprüfung läuft…"
        case .resolvingEmbed: return "Stream wird aufgelöst…"
        case .extractingStream: return "Video wird extrahiert…"
        default: return "Verbinde…"
        }
    }

    // MARK: - Fehler

    private var failedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text("Wiedergabe fehlgeschlagen")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(DS.textPrimary)
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(DS.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            HStack(spacing: 12) {
                Button("Zurück") { phase = .hosterSelection }
                    .buttonStyle(GlassButtonStyle())
                Button("Schließen") { dismiss() }
                    .buttonStyle(GlassButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(DS.textPrimary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .glass()
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Fallback: Hoster-Embed direkt in einer WebView abspielen
struct EmbedPlayerView: View {
    let embedURL: URL
    let title: String
    let onClose: () -> Void

    @State private var webView = WKWebView()

    var body: some View {
        ZStack(alignment: .top) {
            WebViewRepresentable(webView: webView)
                .ignoresSafeArea()
            HStack {
                Text("Web-Player — \(title)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.textPrimary)
                Spacer()
                Button("Schließen") { onClose() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DS.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glass(radius: 10)
            }
            .padding()
            .background(DS.bg.opacity(0.9))
        }
        .onAppear {
            webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
            var request = URLRequest(url: embedURL)
            request.setValue(SerienStreamClient.shared.baseURL + "/", forHTTPHeaderField: "Referer")
            webView.load(request)
        }
    }
}
