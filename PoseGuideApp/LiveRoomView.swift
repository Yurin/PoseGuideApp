import SwiftUI
import LiveKit

struct LiveRoomView: View {
    let role: UserRole
    let roomName: String

    @StateObject private var room = Room()
    @State private var isConnected = false
    @State private var errorMessage: String?
    @State private var remoteTrack: VideoTrack?
    @State private var localTrack: LocalVideoTrack?

    private let eventProxy = RoomEventProxy()

    var body: some View {
        ZStack {
            if isConnected {
                if role == .subject, let t = remoteTrack {
                    LKVideoView(track: t, contentMode: .scaleAspectFit)
                        .ignoresSafeArea()
                } else if role == .photographer, let lt = localTrack {
                    LKVideoView(track: lt, contentMode: .scaleAspectFit)
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                        .overlay(Text("映像を待っています").foregroundColor(.white))
                }
            } else {
                Color.gray.opacity(0.3).ignoresSafeArea()
                    .overlay(Text("接続中...").foregroundColor(.black))
            }

            if let errorMessage {
                VStack {
                    Spacer()
                    Text(errorMessage).foregroundColor(.red).padding()
                }
            }
        }
        .task {
            await connectToRoom(
                roomName: roomName,
                identity: role == .photographer ? "photographer" : "subject"
            )
        }
    }

    @MainActor
    func connectToRoom(roomName: String, identity: String) async {
        let tokenURL = "http://192.168.50.233:3000/token?roomName=\(roomName)&identity=\(identity)"
        guard let url = URL(string: tokenURL) else { return }

        do {
            // 1) トークン取得
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try JSONDecoder().decode([String: String].self, from: data)
            guard let token = result["token"] else { throw URLError(.badServerResponse) }

            // 2) delegate を接続前に登録
            room.removeAllDelegates()
            eventProxy.onRemoteVideo = { v in
                self.remoteTrack = v
                print("Remote video attached:", v.name)
            }
            room.add(delegate: eventProxy)

            // 3) 接続（自動サブスク ON）
            let connectOptions = ConnectOptions(autoSubscribe: true)
            try await room.connect(
                url: "wss://poseguideapp-u7p300v5.livekit.cloud",
                token: token,
                connectOptions: connectOptions
            )
            print("Connected to room:", roomName)
            isConnected = true

            // 4) フェールセーフ：既存公開済みトラックを拾う（複数回試行）
            func attachExistingIfAny() {
                for (_, rp) in room.remoteParticipants {
                    for pub in rp.videoTracks {
                        if let t = pub.track as? VideoTrack {
                            self.remoteTrack = t
                            print("attached existing remote video:", t.name, "pub:", pub.sid)
                            return
                        }
                    }
                }
            }
            // 即時 + 0.3s / 0.8s / 1.5s リトライ
            attachExistingIfAny()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                attachExistingIfAny()
                try? await Task.sleep(nanoseconds: 500_000_000)
                attachExistingIfAny()
                try? await Task.sleep(nanoseconds: 700_000_000)
                attachExistingIfAny()
            }

            // 5) 撮影者のみカメラ publish
            if identity == "photographer" {
                let cam = LocalVideoTrack.createCameraTrack()
                self.localTrack = cam
                try await room.localParticipant.publish(videoTrack: cam)
                print("Published local camera video")
            }

        } catch {
            print("Connection error:", error)
            errorMessage = "接続に失敗しました"
        }
    }
}

