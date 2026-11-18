import AVKit
import Combine
import SwiftUI

struct VideoPlayerView: View {
    let request: VideoRequest
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }

            VStack {
                HStack(spacing: 10) {
                    Text(request.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.58))
                        .clipShape(Capsule())

                    Spacer()

                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.58))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("关闭视频")
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                Spacer()
            }
        }
        .onAppear {
            guard player == nil,
                  let url = URL(string: request.url) else {
                return
            }
            let value = AVPlayer(url: url)
            player = value
            value.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .AVPlayerItemDidPlayToEndTime
            )
        ) { notification in
            guard let item = notification.object as? AVPlayerItem,
                  item === player?.currentItem else {
                return
            }
            close()
        }
    }

    private func close() {
        player?.pause()
        dismiss()
        onClose()
    }
}
