import Foundation
import LiveKit

final class SimpleRoomDelegate: NSObject, RoomDelegate {

    private let onVideo: (VideoTrack) -> Void

    init(onVideo: @escaping (VideoTrack) -> Void) {
        self.onVideo = onVideo
    }

    // リモートのビデオ購読が完了した時（2.8 系）
    func room(_ room: Room,
              participant: RemoteParticipant,
              didSubscribeTrack publication: RemoteTrackPublication,
              track: Track) {
        if let v = track as? VideoTrack {
            onVideo(v)
        }
    }

    // 既存パブリケーションを拾うための publish フックも入れておく
    func room(_ room: Room,
              participant: RemoteParticipant,
              didPublishTrack publication: RemoteTrackPublication) {
        if let v = publication.track as? VideoTrack {
            onVideo(v)
        }
    }
}

