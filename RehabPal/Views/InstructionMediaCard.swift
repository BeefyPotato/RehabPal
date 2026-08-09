import AVKit
import SwiftUI

enum InstructionMediaKind: String {
    case balance
    case squeeze
    case sheepDrop
    case wristAssessment
    case fingerROM

    var title: String {
        switch self {
        case .balance: "Tilt your wrist to guide the ball"
        case .squeeze: "Close, hold, then fully reopen"
        case .sheepDrop: "Bring all five fingertips together, then release over the pen"
        case .wristAssessment: "Move smoothly in each direction"
        case .fingerROM: "Bend and straighten one finger"
        }
    }
}

struct InstructionMediaCard: View {
    let kind: InstructionMediaKind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let player, !reduceMotion {
                    VideoPlayer(player: player)
                        .onAppear { player.play() }
                } else {
                    ZStack {
                        LinearGradient(colors: [.teal.opacity(0.35), .blue.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: previewSystemImage)
                            .font(.system(size: 70)).foregroundStyle(.white)
                    }
                }
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            Text(kind.title).font(.headline)
            Text("Muted demonstration • loops automatically")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 520)
        .onAppear {
            guard player == nil, let url = Bundle.main.url(forResource: kind.rawValue, withExtension: "mp4") else { return }
            let item = AVPlayerItem(url: url)
            player = AVPlayer(playerItem: item)
            player?.isMuted = true
            NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { _ in
                player?.seek(to: .zero)
                player?.play()
            }
        }
    }

    private var previewSystemImage: String {
        switch kind {
        case .balance, .wristAssessment:
            "hand.draw"
        case .squeeze, .fingerROM:
            "hand.raised.fingers.spread"
        case .sheepDrop:
            "pawprint.fill"
        }
    }
}
