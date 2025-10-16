import SwiftUI
import LiveKit

struct LiveRoomView: View {
    let role: UserRole
    let roomName: String

    @StateObject private var room = Room()
    @State private var localTrack: LocalVideoTrack?
    @State private var remoteTrack: VideoTrack?
    @State private var isConnected = false
    @State private var errorMessage: String?

    private let eventProxy = RoomEventProxy()

    var body: some View {
        ZStack {
            if isConnected {
                if role == .subject, let remoteTrack {
                    LKVideoView(track: remoteTrack, contentMode: .scaleAspectFit)
                        .ignoresSafeArea()
                } else if role == .photographer, let localTrack {
                    LKVideoView(track: localTrack, contentMode: .scaleAspectFit)
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
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                }
            }
        }
        .task {
            await connectToRoom(roomName: roomName,
                                identity: role == .photographer ? "photographer" : "subject")
        }
    }

    @MainActor
    func connectToRoom(roomName: String, identity: String) async {
        let tokenURL = "http://192.168.50.42:3000/token?roomName=\(roomName)&identity=\(identity)"
        guard let url = URL(string: tokenURL) else { return }

        do {
            // トークン取得
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try JSONDecoder().decode([String: String].self, from: data)
            guard let token = result["token"] else { throw URLError(.badServerResponse) }

            // イベント設定
            eventProxy.onRemoteVideo = { v in
                Task { @MainActor in
                    remoteTrack = v
                }
            }
            room.add(delegate: eventProxy)

            // 接続
            try await room.connect(
                url: "wss://poseguideapp-u7p300v5.livekit.cloud",
                token: token
            )

            // 撮影者：カメラ起動＆配信
            if role == .photographer {
                localTrack = LocalVideoTrack.createCameraTrack()
                if let localTrack {
                    try await room.localParticipant.publish(videoTrack: localTrack)
                }
            }

            isConnected = true
            print("✅ Connected to room:", roomName)

        } catch {
            print("❌ Connection error:", error)
            errorMessage = "接続に失敗しました"
        }
    }
}

