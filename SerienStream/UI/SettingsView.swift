import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var catalog: CatalogStore
    @EnvironmentObject private var history: WatchHistoryStore

    @State private var endpointStatus: [String: Bool] = [:]
    @State private var probing = false
    @State private var activeEndpoint: String = SerienStreamClient.shared.baseURL

    private let client = SerienStreamClient.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    endpointSection
                    playbackSection
                    dataSection
                    diagnosticsSection
                    aboutSection
                }
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .background(DS.bg.ignoresSafeArea())
            .navigationTitle("Einstellungen")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await reprobe() }
        }
    }

    // MARK: - Endpoints

    private var endpointSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Verbindung")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(DS.textPrimary)
                Spacer()
                if probing {
                    ProgressView().tint(DS.accent).scaleEffect(0.8)
                } else {
                    Button {
                        Task { await reprobe() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(DS.accent)
                            .padding(8)
                            .glass(radius: 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            Text("Die App wählt beim Start automatisch den ersten erreichbaren Server. Tippen zum manuellen Wechseln.")
                .font(.footnote)
                .foregroundColor(DS.textSecondary)
                .padding(.horizontal)

            ForEach(SerienStreamClient.endpoints, id: \.url) { ep in
                endpointRow(ep)
            }
        }
    }

    private func endpointRow(_ ep: SerienStreamClient.Endpoint) -> some View {
        let isActive = activeEndpoint == ep.url
        let reachable = endpointStatus[ep.url]

        return Button {
            client.selectEndpoint(ep.url, manual: true)
            activeEndpoint = ep.url
            catalog.clearCache()
            Task { await catalog.loadAll(force: true) }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(reachable == nil ? DS.textTertiary : (reachable == true ? Color.green : Color.red))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(ep.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(DS.textPrimary)
                        if isActive {
                            Text("AKTIV")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundColor(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DS.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text(ep.note)
                        .font(.system(size: 11))
                        .foregroundColor(DS.textSecondary)
                    Text(ep.url)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(DS.textTertiary)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(DS.accent)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.glassFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isActive ? DS.accent.opacity(0.6) : DS.glassStroke, lineWidth: 1)
            )
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }

    private func reprobe() async {
        probing = true
        endpointStatus = [:]
        for ep in SerienStreamClient.endpoints {
            let ok = await client.probe(ep.url)
            endpointStatus[ep.url] = ok
        }
        probing = false
    }

    // MARK: - Wiedergabe

    @State private var preferredHoster: String = UserDefaults.standard.string(forKey: "serienstream.preferredHoster") ?? ""
    @State private var autoplay: Bool = UserDefaults.standard.object(forKey: "serienstream.autoplay") as? Bool ?? true
    @State private var preferGerman: Bool = UserDefaults.standard.object(forKey: "serienstream.preferGerman") as? Bool ?? true

    private let knownHosters = ["VOE", "Doodstream", "Streamtape", "Vidoza", "Filemoon", "Voe"]
    private let germanFlag = "de"

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Wiedergabe")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(DS.textPrimary)
                .padding(.horizontal)

            VStack(spacing: 0) {
                toggleRow(icon: "forward.fill", title: "Autoplay nächste Episode", subtitle: "Startet die nächste Folge automatisch", value: $autoplay)
                    .onChange(of: autoplay) { v in UserDefaults.standard.set(v, forKey: "serienstream.autoplay") }
                Divider().background(DS.glassStroke)
                toggleRow(icon: "globe", title: "Deutsch bevorzugen", subtitle: "Deutsche Hoster werden zuerst angezeigt", value: $preferGerman)
                    .onChange(of: preferGerman) { v in UserDefaults.standard.set(v, forKey: "serienstream.preferGerman") }
            }
            .glass(radius: 14)
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DS.accent)
                        .frame(width: 34, height: 34)
                        .background(DS.accent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Text("Bevorzugter Hoster")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DS.textPrimary)
                    Spacer()
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        hosterChip("Automatisch", value: "")
                        ForEach(["VOE", "Doodstream", "Streamtape", "Vidoza", "Filemoon"], id: \.self) { h in
                            hosterChip(h, value: h)
                        }
                    }
                }
            }
            .padding(14)
            .glass(radius: 14)
            .padding(.horizontal)
        }
    }

    private func hosterChip(_ label: String, value: String) -> some View {
        let active = preferredHoster == value
        return Button {
            preferredHoster = value
            UserDefaults.standard.set(value, forKey: "serienstream.preferredHoster")
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(active ? .black : DS.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(active ? DS.accent : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(icon: String, title: String, subtitle: String, value: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(DS.accent)
                .frame(width: 34, height: 34)
                .background(DS.accent.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(DS.textSecondary)
            }
            Spacer()
            Toggle("", isOn: value)
                .labelsHidden()
                .tint(DS.accent)
        }
        .padding(14)
    }

    // MARK: - Daten

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Daten")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(DS.textPrimary)
                .padding(.horizontal)

            settingsButton(
                icon: "arrow.triangle.2.circlepath",
                title: "Katalog neu laden",
                subtitle: "Serienliste und Cover aktualisieren"
            ) {
                Task { await catalog.loadAll(force: true) }
            }

            settingsButton(
                icon: "trash",
                title: "Verlauf löschen",
                subtitle: "Weiterschauen und Gesehen-Markierungen entfernen",
                destructive: true
            ) {
                history.clear()
            }

            settingsButton(
                icon: "xmark.bin",
                title: "Cache zurücksetzen",
                subtitle: "App komplett neu synchronisieren",
                destructive: true
            ) {
                catalog.clearCache()
                Task { await catalog.loadAll(force: true) }
            }
        }
    }

    private func settingsButton(icon: String, title: String, subtitle: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(destructive ? .red : DS.accent)
                    .frame(width: 34, height: 34)
                    .background((destructive ? Color.red : DS.accent).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DS.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(DS.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.textTertiary)
            }
            .padding(14)
            .glass(radius: 14)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Diagnose

    private var diagnosticsSection: some View {
        DiagnosticsView()
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Über")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(DS.textPrimary)
                .padding(.horizontal)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 22))
                        .foregroundColor(DS.accent)
                    Text("SerienStream")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(DS.textPrimary)
                    Spacer()
                    Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(DS.textTertiary)
                }
                Text("Inoffizielle Client-App für serienstream.to. Alle Inhalte stammen von der Website — diese App hostet nichts selbst.")
                    .font(.system(size: 12))
                    .foregroundColor(DS.textSecondary)
                    .lineSpacing(3)
            }
            .padding(16)
            .glass(radius: 14)
            .padding(.horizontal)
        }
    }
}
