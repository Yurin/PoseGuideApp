import Foundation
import LiveKit

@MainActor
final class RoomEventProxy: NSObject, RoomDelegate {

    var onRemoteVideo: ((VideoTrack) -> Void)?

    // 参加/退出（デバッグ）
    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        print("Remote participant connected:", participant.identity ?? "(nil)")
    }
    func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        print("Remote participant disconnected:", participant.identity ?? "(nil)")
    }

    // 参考ログ（publish 検知）
    func room(_ room: Room,
              participant: RemoteParticipant,
              didPublishTrack publication: RemoteTrackPublication) {
        print("didPublishTrack:", publication.sid)
    }

    // ▼ SDK 差分に備えて 2 パターン実装（どちらか一方が必ず呼ばれる）
    // A) (track, publication) 順
    func room(_ room: Room,
              participant: RemoteParticipant,
              didSubscribeTrack track: Track,
              publication: RemoteTrackPublication) {
        if let v = track as? VideoTrack {
            print("didSubscribeTrack A:", v.name, "pub:", publication.sid)
            onRemoteVideo?(v)
        } else {
            print("didSubscribeTrack A: non-video")
        }
    }

    // B) (publication, track) 順
    func room(_ room: Room,
              participant: RemoteParticipant,
              didSubscribeTrack publication: RemoteTrackPublication,
              track: Track) {
        if let v = track as? VideoTrack {
            print("didSubscribeTrack B:", v.name, "pub:", publication.sid)
            onRemoteVideo?(v)
        } else {
            print("didSubscribeTrack B: non-video")
        }
    }
}

