import Foundation
import LiveKit

@MainActor
final class RoomEventProxy: NSObject, RoomDelegate, ParticipantDelegate {

    // 映像・データ受け渡し用コールバック
    var onRemoteVideo: ((VideoTrack) -> Void)?
    var onDataMessage: ((Data, RemoteParticipant?, String?) -> Void)?

    // リモート参加者の出入り通知（任意）
    var onRemoteConnected: ((RemoteParticipant) -> Void)?
    var onRemoteDisconnected: ((RemoteParticipant) -> Void)?

    // MARK: RoomDelegate

    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        print("[Proxy] remote connected:", String(describing: participant.identity))
        onRemoteConnected?(participant)

        // 接続と同時に、その参加者へ ParticipantDelegate をアタッチ
        participant.add(delegate: self)
        print("[Proxy] attached ParticipantDelegate to:", String(describing: participant.identity))
    }

    func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        print("[Proxy] remote disconnected:", String(describing: participant.identity))
        onRemoteDisconnected?(participant)
    }

    func room(_ room: Room,
              participant: RemoteParticipant,
              didPublishTrack publication: RemoteTrackPublication) {
        print("[Proxy] didPublishTrack:", publication.sid, "kind:", publication.kind.rawValue)
    }

    func room(_ room: Room,
              participant: RemoteParticipant,
              didSubscribeTrack publication: RemoteTrackPublication,
              track: Track) {
        if let v = track as? VideoTrack {
            print("[Proxy] didSubscribeTrack video:", v.name, "pub:", publication.sid)
            onRemoteVideo?(v)
        }
    }

    func room(_ room: Room,
              participant: RemoteParticipant?,
              didReceiveData data: Data,
              forTopic topic: String?) {
        let fromStr = String(describing: participant?.identity)
        print("[Proxy] RoomDelegate didReceiveData bytes=\(data.count) topic=\(topic ?? "(nil)") from=\(fromStr)")
        onDataMessage?(data, participant, topic)
    }


    func participant(_ participant: RemoteParticipant,
                     didReceive data: Data,
                     forTopic topic: String?) {
        let fromStr = String(describing: participant.identity)
        print("[Proxy] ParticipantDelegate didReceive bytes=\(data.count) topic=\(topic ?? "(nil)") from=\(fromStr)")
        onDataMessage?(data, participant, topic)
    }
}
