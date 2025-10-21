import Foundation
import LiveKit

/// 映像の購読イベントだけ拾う最小デリゲート
final class SimpleRoomDelegate: NSObject, RoomDelegate {

    private let onVideo: (VideoTrack) -> Void

    init(onVideo: @escaping (VideoTrack) -> Void) {
        self.onVideo = onVideo
    }

    // 2.8.1 のシグネチャ（RemoteParticipant / publication / track の順）
    func room(_ room: Room,
              participant: RemoteParticipant,
              didSubscribeTrack publication: RemoteTrackPublication,
              track: Track) {
        if let v = track as? VideoTrack {
            print("[DELEGATE] didSubscribeTrack:", v.name, "pub:", publication.sid)
            onVideo(v)
        }
    }

    // 相手が join した直後に、既存トラックを拾えるよう軽く再確認
    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        print("[DELEGATE] remote connected:", participant.identity ?? "(nil)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            for pub in participant.videoTracks {
                if let t = pub.track as? VideoTrack {
                    print("[DELEGATE] pick existing from participant:", t.name)
                    self.onVideo(t)
                    break
                }
            }
        }
    }
}


