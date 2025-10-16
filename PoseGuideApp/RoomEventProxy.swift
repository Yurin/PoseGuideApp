import Foundation
import LiveKit

final class RoomEventProxy: NSObject, RoomDelegate, @unchecked Sendable {
    var onRemoteVideo: ((VideoTrack) -> Void)?

    func room(_ room: Room,
              participant: RemoteParticipant,
              didSubscribeTrack publication: RemoteTrackPublication,
              track: Track) {
        if let videoTrack = track as? VideoTrack {
            onRemoteVideo?(videoTrack)
        }
    }
}

