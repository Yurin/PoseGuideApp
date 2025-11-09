//import Foundation
//import LiveKit
//
//@MainActor
//final class RoomEventProxy: NSObject, RoomDelegate, ParticipantDelegate {
//
//    var onRemoteVideo: ((VideoTrack) -> Void)?
//    var onDataMessage: ((Data, Participant?, String?) -> Void)?
//
//    // MARK: RoomDelegate
//
//    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
//        print("[Proxy] remote connected:", participant.identity ?? "(nil)")
//        // 参加直後に ParticipantDelegate を付与
//        participant.add(delegate: self)
//        print("[Proxy] attached ParticipantDelegate to:", participant.identity ?? "(nil)")
//    }
//
//    func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
//        print("[Proxy] remote disconnected:", participant.identity ?? "(nil)")
//    }
//
//    func room(_ room: Room,
//              participant: RemoteParticipant,
//              didPublishTrack publication: RemoteTrackPublication) {
//        print("[Proxy] didPublishTrack:", publication.sid, "kind:", publication.kind.rawValue)
//    }
//
//    func room(_ room: Room,
//              participant: RemoteParticipant,
//              didSubscribeTrack publication: RemoteTrackPublication,
//              track: Track) {
//        if let v = track as? VideoTrack {
//            print("[Proxy] didSubscribeTrack video:", v.name, "pub:", publication.sid)
//            onRemoteVideo?(v)
//        }
//    }
//
//    // LiveKit 2.8.1 の RoomDelegate シグネチャ
//    func room(_ room: Room,
//              participant: Participant?,
//              didReceiveData data: Data,
//              forTopic topic: String?) {
//        let fromStr = String(describing: participant?.identity)
//        print("[Proxy][RoomDelegate] didReceiveData bytes=\(data.count) topic=\(topic ?? "(nil)") from=\(fromStr)")
//        onDataMessage?(data, participant, topic)
//    }
//
//    // MARK: ParticipantDelegate（こちら経由で届く場合もある）
//    func participant(_ participant: Participant,
//                     didReceiveData data: Data,
//                     forTopic topic: String?) {
//        let fromStr = String(describing: participant.identity)
//        print("[Proxy][ParticipantDelegate] didReceiveData bytes=\(data.count) topic=\(topic ?? "(nil)") from=\(fromStr)")
//        onDataMessage?(data, participant, topic)
//    }
//}
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

    // LiveKit 2.8.x の RoomDelegate でのデータ受信
    func room(_ room: Room,
              participant: RemoteParticipant?,
              didReceiveData data: Data,
              forTopic topic: String?) {
        let fromStr = String(describing: participant?.identity)
        print("[Proxy] RoomDelegate didReceiveData bytes=\(data.count) topic=\(topic ?? "(nil)") from=\(fromStr)")
        onDataMessage?(data, participant, topic)
    }

    // MARK: ParticipantDelegate（参加者ごと）

    func participant(_ participant: RemoteParticipant,
                     didReceive data: Data,
                     forTopic topic: String?) {
        let fromStr = String(describing: participant.identity)
        print("[Proxy] ParticipantDelegate didReceive bytes=\(data.count) topic=\(topic ?? "(nil)") from=\(fromStr)")
        onDataMessage?(data, participant, topic)
    }
}
