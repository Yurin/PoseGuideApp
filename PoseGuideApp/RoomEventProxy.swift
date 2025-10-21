import Foundation
import LiveKit

@MainActor
final class RoomEventProxy: NSObject, RoomDelegate {

    var onRemoteVideo: ((VideoTrack) -> Void)?
    var onDataMessage: ((Data, RemoteParticipant?, String?) -> Void)?

    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        print("Remote participant connected:", participant.identity ?? "(nil)")
    }

    func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        print("Remote participant disconnected:", participant.identity ?? "(nil)")
    }

    func room(_ room: Room,
              participant: RemoteParticipant,
              didPublishTrack publication: RemoteTrackPublication) {
        print("didPublishTrack:", publication.sid)
    }

    // どちらのシグネチャでも受け取れるように両方実装
    func room(_ room: Room,
              participant: RemoteParticipant,
              didSubscribeTrack track: Track,
              publication: RemoteTrackPublication) {
        if let v = track as? VideoTrack {
            print("didSubscribeTrack A:", v.name, "pub:", publication.sid)
            onRemoteVideo?(v)
        }
    }

    func room(_ room: Room,
              participant: RemoteParticipant,
              didSubscribeTrack publication: RemoteTrackPublication,
              track: Track) {
        if let v = track as? VideoTrack {
            print("didSubscribeTrack B:", v.name, "pub:", publication.sid)
            onRemoteVideo?(v)
        }
    }

    func room(_ room: Room,
              didReceive data: Data,
              participant: RemoteParticipant?,
              topic: String?) {
        onDataMessage?(data, participant, topic)
    }
}

