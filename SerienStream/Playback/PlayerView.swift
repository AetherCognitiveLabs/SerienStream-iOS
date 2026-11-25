import SwiftUI
import AVKit

struct PlayerScreen: View {
    let stream: StreamResult
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }
        }
        .onAppear {
            let asset = AVURLAsset(url: stream.streamURL, options: ["AVURLAssetHTTPHeaderFieldsKey": stream.headers])
            let item = AVPlayerItem(asset: asset)
            let p = AVPlayer(playerItem: item)
            self.player = p
            p.play()
        }
        .onDisappear {
            player?.pause()
        }
    }
}
