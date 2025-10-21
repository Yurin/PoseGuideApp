import SwiftUI
import LiveKit
import Photos

struct LiveRoomView: View {
    let role: UserRole
    let roomName: String

    @StateObject private var room = Room()

    @State private var isConnected = false
    @State private var errorMessage: String?

    // 映像
    @State private var remoteTrack: VideoTrack?
    @State private var localTrack: LocalVideoTrack?
    @State private var localPub: LocalTrackPublication?   // unpublish 用

    // ガイド
    @State private var guideFrame: UIImage? = UIImage(named: "frame_sample")
    @State private var guide = GuideState()
    @State private var guideLocked = false

    // 被写体 ジェスチャ一時値
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero

    // 撮影者 カメラ向き
    enum CamPos { case front, back }
    @State private var camPos: CamPos = .front

    private let eventProxy = RoomEventProxy()

    var body: some View {
        ZStack {
            // ===== 映像レイヤー =====
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

            // ===== ガイド（両者表示。編集は被写体のみ） =====
            if let frame = guideFrame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(CGFloat(guide.scale))
                    .opacity(guide.opacity)
                    .offset(x: CGFloat(guide.offsetX), y: CGFloat(guide.offsetY))
                    .allowsHitTesting(role == .subject)
                    .gesture(role == .subject ? guideGestures : nil)
                    .animation(.easeInOut(duration: 0.15), value: guide)
            }

            // ===== 被写体 UI（調整・確定） =====
            if role == .subject {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Text("フレーム調整").foregroundColor(.white).bold()
                        Slider(
                            value: Binding(
                                get: { guide.opacity },
                                set: { newVal in
                                    guide.opacity = newVal
                                    Task { await sendGuide(.update) }
                                }
                            ),
                            in: 0...1
                        )
                        .frame(width: 160)

                        Spacer()

                        Button("確定") {
                            Task { await sendGuide(.lock) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(14)
                    .padding(.bottom, 20)
                }
            }

            // ===== 撮影者 UI（右下のカメラ切替、下中央のシャッター） =====
            if role == .photographer {
                // 右下フローティング切替ボタン
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            Task { await switchCamera(camPos == .front ? .back : .front) }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(width: 56, height: 56)
                                .background(.white)
                                .clipShape(Circle())
                                .shadow(radius: 6, y: 2)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, guideLocked ? 110 : 24)
                    }
                }
                .ignoresSafeArea()

                // シャッター（ガイド確定後のみ）
                if guideLocked {
                    VStack {
                        Spacer()
                        Button {
                            Task { await captureAndSaveCurrentFrame() }
                        } label: {
                            ZStack {
                                Circle().fill(Color.white.opacity(0.9)).frame(width: 72, height: 72)
                                Circle().stroke(Color.white, lineWidth: 3).frame(width: 84, height: 84)
                            }
                        }
                        .padding(.bottom, 28)
                    }
                    .ignoresSafeArea()
                }
            }

            if let errorMessage {
                VStack { Spacer(); Text(errorMessage).foregroundColor(.red).padding() }
            }
        }
        .task {
            await connectToRoom(
                roomName: roomName,
                identity: role == .photographer ? "photographer" : "subject"
            )
        }
    }

    // MARK: - ジェスチャ（被写体）
    private var guideGestures: some Gesture {
        SimultaneousGesture(
            DragGesture()
                .onChanged { v in
                    guide.offsetX = Double(lastOffset.width + v.translation.width)
                    guide.offsetY = Double(lastOffset.height + v.translation.height)
                    Task { await sendGuide(.update) }
                }
                .onEnded { _ in
                    lastOffset = CGSize(width: CGFloat(guide.offsetX), height: CGFloat(guide.offsetY))
                },
            MagnificationGesture()
                .onChanged { value in
                    guide.scale = Double(lastScale * value)
                    Task { await sendGuide(.update) }
                }
                .onEnded { _ in
                    lastScale = CGFloat(guide.scale)
                }
        )
    }

    // MARK: - 接続処理
    @MainActor
    func connectToRoom(roomName: String, identity: String) async {
        // あなたのトークンサーバ（Mac）の IP に合わせる
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
            eventProxy.onDataMessage = { data, _, _ in
                self.handleIncomingData(data)
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

            // 4) 既存公開済みを拾う（保険）
            attachExistingRemoteIfAny()

            // 5) 撮影者のみカメラ publish（初期向き）
            if identity == "photographer" {
                try await publishCamera(position: camPos)
            }

        } catch {
            print("Connection error:", error)
            errorMessage = "接続に失敗しました"
        }
    }

    @MainActor
    private func attachExistingRemoteIfAny() {
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

    // MARK: - DataChannel 送受信（被写体→撮影者）
    @MainActor
    private func sendGuide(_ type: GuideEventType) async {
        guard role == .subject else { return }
        let msg = GuideMessage(type: type, state: guide, roomName: roomName)
        do {
            let data = try JSONEncoder().encode(msg)
            // 引数順: topic → reliable
            let options = DataPublishOptions(topic: "guide", reliable: true)
            try await room.localParticipant.publish(data: data, options: options)
            if type == .lock { guideLocked = true }
        } catch {
            print("sendGuide error:", error)
        }
    }

    @MainActor
    private func handleIncomingData(_ data: Data) {
        guard let msg = try? JSONDecoder().decode(GuideMessage.self, from: data),
              msg.roomName == roomName else { return }

        if role == .photographer {
            self.guide = msg.state
            if msg.type == .lock {
                self.guideLocked = true
                print("guide locked by subject")
            }
        }
    }

    // MARK: - カメラ制御（撮影者）
    @MainActor
    private func publishCamera(position: CamPos) async throws {
        // 既存トラックがあり、CameraCapturer を保持していればキャプチャだけ切替
        if let track = localTrack,
           let capturer = track.capturer as? CameraCapturer {
            try await capturer.set(cameraPosition: position == .front ? .front : .back)
            camPos = position
            print("Switched camera (reuse track): \(position == .front ? "front" : "back")")
            return
        }

        // 初回: トラック作成して publish
        let options = CameraCaptureOptions(position: position == .front ? .front : .back)
        let cam = LocalVideoTrack.createCameraTrack(options: options)
        self.localTrack = cam
        let pub: LocalTrackPublication = try await room.localParticipant.publish(videoTrack: cam)
        self.localPub = pub
        camPos = position
        print("Published camera video (\(position == .front ? "front" : "back"))")
    }

    // ※ ファイル内に一つだけ
    @MainActor
    private func switchCamera(_ to: CamPos) async {
        guard role == .photographer else { return }
        if camPos == to { return }
        do {
            // 可能ならキャプチャだけ切替、無ければ初期 publish
            if let track = localTrack,
               let capturer = track.capturer as? CameraCapturer {
                try await capturer.set(cameraPosition: to == .front ? .front : .back)
                camPos = to
                print("Switched camera (set position): \(to == .front ? "front" : "back")")
            } else {
                try await publishCamera(position: to)
            }
        } catch {
            print("switchCamera error:", error)
            self.errorMessage = "カメラ切替に失敗しました"
        }
    }

    // MARK: - 撮影（撮影者・確定後のみ）
    @MainActor
    private func captureAndSaveCurrentFrame() async {
        guard role == .photographer, guideLocked else { return }

        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized else {
            self.errorMessage = "写真への保存が許可されていません（設定で許可してください）"
            return
        }

        let renderer = ImageRenderer(content: snapshotContentView)
        renderer.scale = UIScreen.main.scale

        if let uiImage = renderer.uiImage {
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
            }) { success, err in
                Task { @MainActor in
                    if success {
                        print("Saved photo to library")
                    } else {
                        print("Save failed:", err?.localizedDescription ?? "")
                        self.errorMessage = "保存に失敗しました"
                    }
                }
            }
        } else {
            self.errorMessage = "撮影に失敗しました"
        }
    }

    @ViewBuilder
    private var snapshotContentView: some View {
        ZStack {
            if role == .subject, let t = remoteTrack {
                LKVideoView(track: t, contentMode: .scaleAspectFit)
            } else if role == .photographer, let lt = localTrack {
                LKVideoView(track: lt, contentMode: .scaleAspectFit)
            } else { Color.black }

            if let frame = guideFrame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(CGFloat(guide.scale))
                    .opacity(guide.opacity)
                    .offset(x: CGFloat(guide.offsetX), y: CGFloat(guide.offsetY))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

