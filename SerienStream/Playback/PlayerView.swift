import SwiftUI
import AVKit

/// Nativer AVPlayer mit Resume-Position, Positions-Tracking und Autoplay nächste Episode.
struct PlayerScreen: View {
    let stream: StreamResult
    let title: String
    let episode: EpisodeRef
    let seriesTitle: String
    var hasNextEpisode: Bool = false
    var onNextEpisode: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var history: WatchHistoryStore
    @State private var player: AVPlayer?
    @State private var endObserver: NSObjectProtocol?
    @State private var timeObserver: Any?
    @State private var showNextOverlay = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }

            if showNextOverlay, hasNextEpisode {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            onNextEpisode?()
                        } label: {
                            HStack(spacing: 8) {
                                Text("Nächste Episode")
                                    .font(.system(size: 15, weight: .semibold))
                                Image(systemName: "forward.end.fill")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(DS.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 20)
                        .padding(.bottom, 90)
                    }
                }
                .transition(.opacity)
            }
        }
        .onAppear { startPlayback() }
        .onDisappear { stopPlayback() }
    }

    private func startPlayback() {
        let asset = AVURLAsset(url: stream.streamURL, options: ["AVURLAssetHTTPHeaderFieldsKey": stream.headers])
        let item = AVPlayerItem(asset: asset)
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true
        self.player = p

        // Resume
        let resumePos = history.position(seriesSlug: episode.seriesSlug, season: episode.season, episode: episode.episode)
        if resumePos > 5 {
            p.seek(to: CMTime(seconds: resumePos, preferredTimescale: 600))
        }
        p.play()

        // Positions-Tracking alle 5 Sekunden
        let interval = CMTime(seconds: 5, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak p] time in
            guard let p, let item = p.currentItem else { return }
            let pos = time.seconds
            let dur = item.duration.seconds
            guard pos.isFinite, pos > 0 else { return }
            let duration = dur.isFinite && dur > 0 ? dur : 0
            Task { @MainActor in
                history.savePosition(seriesSlug: episode.seriesSlug, seriesTitle: seriesTitle, season: episode.season, episode: episode.episode, position: pos, duration: duration)
            }
        }

        // Ende erkennen → Overlay bzw. Autoplay
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            Task { @MainActor in
                let id = WatchHistoryStore.entryId(seriesSlug: episode.seriesSlug, season: episode.season, episode: episode.episode)
                _ = id
                history.savePosition(seriesSlug: episode.seriesSlug, seriesTitle: seriesTitle, season: episode.season, episode: episode.episode, position: 1, duration: 1) // als gesehen werten
                if UserDefaults.standard.object(forKey: "serienstream.autoplay") as? Bool ?? true {
                    if hasNextEpisode {
                        onNextEpisode?()
                    }
                } else if hasNextEpisode {
                    withAnimation { showNextOverlay = true }
                }
            }
        }
    }

    private func stopPlayback() {
        // Finale Position speichern
        if let p = player, let item = p.currentItem {
            let pos = p.currentTime().seconds
            let dur = item.duration.seconds
            if pos.isFinite, pos > 0 {
                let duration = dur.isFinite && dur > 0 ? dur : 0
                history.savePosition(seriesSlug: episode.seriesSlug, seriesTitle: seriesTitle, season: episode.season, episode: episode.episode, position: pos, duration: duration)
            }
        }
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        if let obs = timeObserver, let p = player {
            p.removeTimeObserver(obs)
            timeObserver = nil
        }
        player?.pause()
    }
}
