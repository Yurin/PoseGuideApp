import Foundation
import LiveKit

final class SimpleRoomDelegate: NSObject, RoomDelegate {

    private let onVideo: (VideoTrack) -> Void

    init(onVideo: @escaping (VideoTrack) -> Void) {
        self.onVideo = onVideo
    }

    func room(_ room: Room,
              participant: RemoteParticipant,
              didSubscribeTrack publication: RemoteTrackPublication,
              track: Track) {
        if let v = track as? VideoTrack {
            onVideo(v)
        }
    }

    func room(_ room: Room,
              participant: RemoteParticipant,
              didPublishTrack publication: RemoteTrackPublication) {
        if let v = publication.track as? VideoTrack {
            onVideo(v)
        }
    }
}

