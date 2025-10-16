import SwiftUI
import LiveKit

struct LKVideoView: UIViewRepresentable {
    let track: VideoTrack
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeUIView(context: Context) -> VideoView {
        let view = VideoView()
        view.contentMode = contentMode
        view.track = track
        return view
    }

    func updateUIView(_ uiView: VideoView, context: Context) {
        if uiView.track?.sid != track.sid {
            uiView.track = track
        }
    }
}

