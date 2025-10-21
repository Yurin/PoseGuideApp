//import SwiftUI
//import LiveKit
//import Photos
//
//struct LiveRoomView: View {
//    let role: UserRole
//    let roomName: String
//
//    @StateObject private var room = Room()
//
//    @State private var isConnected = false
//    @State private var errorMessage: String?
//
//    // 二重接続防止
//    @State private var didStartConnect = false
//
//    // 映像
//    @State private var remoteTrack: VideoTrack?
//    @State private var localTrack: LocalVideoTrack?
//    @State private var localPub: LocalTrackPublication?
//
//    // ガイド
//    @State private var guideFrame: UIImage? = UIImage(named: "pose_guide1_silhouette")
//    @State private var guide = GuideState()
//    @State private var guideLocked = false
//
//    // 被写体 ジェスチャ一時値
//    @State private var lastScale: CGFloat = 1.0
//    @State private var lastOffset: CGSize = .zero
//
//    // 撮影者 カメラ向き
//    enum CamPos { case front, back }
//    @State private var camPos: CamPos = .front
//
//    // 参加者 SID のトラッキング（任意のデバッグ用）
//    @State private var remoteSids: Set<Participant.Sid> = []
//
//    private let eventProxy = RoomEventProxy()
//
//    var body: some View {
//        ZStack {
//            // ===== 映像レイヤー =====
//            if isConnected {
//                if role == .subject, let t = remoteTrack {
//                    LKVideoView(track: t, contentMode: .scaleAspectFit)
//                        .ignoresSafeArea()
//                } else if role == .photographer, let lt = localTrack {
//                    LKVideoView(track: lt, contentMode: .scaleAspectFit)
//                        .ignoresSafeArea()
//                } else {
//                    Color.black.ignoresSafeArea()
//                        .overlay(Text("映像を待っています").foregroundColor(.white))
//                }
//            } else {
//                Color.gray.opacity(0.3).ignoresSafeArea()
//                    .overlay(Text("接続中...").foregroundColor(.black))
//            }
//
//            // ===== ガイド（両者表示。編集は被写体のみ、ロックで無効化） =====
//            if let frame = guideFrame {
//                Image(uiImage: frame)
//                    .resizable()
//                    .scaledToFit()
//                    .scaleEffect(CGFloat(guide.scale))
//                    .opacity(guide.opacity)
//                    .offset(x: CGFloat(guide.offsetX), y: CGFloat(guide.offsetY))
//                    .allowsHitTesting(role == .subject && !guideLocked)
//                    .gesture(role == .subject && !guideLocked ? guideGestures : nil)
//                    .animation(.easeInOut(duration: 0.15), value: guideLocked)
//                    .animation(.easeInOut(duration: 0.15), value: guide)
//            }
//
//            // ===== 被写体 UI（確定） =====
//            if role == .subject {
//                VStack {
//                    Spacer()
//                    HStack {
//                        Spacer()
//                        Button(guideLocked ? "確定済み" : "確定") {
//                            print("[UI] Lock button tapped")
//                            Task { await sendGuide(.lock) }
//                        }
//                        .buttonStyle(.borderedProminent)
//                        .disabled(guideLocked)
//                    }
//                    .padding()
//                    .background(Color.black.opacity(0.5))
//                    .cornerRadius(14)
//                    .padding(.bottom, 20)
//                }
//            }
//
//            // ===== 撮影者 UI（右下カメラ切替、ロック後はシャッター） =====
//            if role == .photographer {
//                VStack {
//                    Spacer()
//                    HStack {
//                        Spacer()
//                        Button {
//                            print("[UI] Camera switch tapped (current: \(camPos == .front ? "front" : "back"))")
//                            Task { await switchCamera(camPos == .front ? .back : .front) }
//                        } label: {
//                            Image(systemName: "arrow.triangle.2.circlepath.camera")
//                                .font(.system(size: 20, weight: .semibold))
//                                .foregroundColor(.black)
//                                .frame(width: 56, height: 56)
//                                .background(.white)
//                                .clipShape(Circle())
//                                .shadow(radius: 6, y: 2)
//                        }
//                        .padding(.trailing, 20)
//                        .padding(.bottom, guideLocked ? 110 : 24)
//                    }
//                }
//                .ignoresSafeArea()
//
//                if guideLocked {
//                    VStack {
//                        Spacer()
//                        Button {
//                            print("[UI] Shutter tapped")
//                            Task { await captureAndSaveCurrentFrame() }
//                        } label: {
//                            ZStack {
//                                Circle().fill(Color.white.opacity(0.9)).frame(width: 72, height: 72)
//                                Circle().stroke(Color.white, lineWidth: 3).frame(width: 84, height: 84)
//                            }
//                        }
//                        .padding(.bottom, 28)
//                    }
//                    .ignoresSafeArea()
//                }
//            }
//
//            if let errorMessage {
//                VStack { Spacer(); Text(errorMessage).foregroundColor(.red).padding() }
//            }
//        }
//        // 画面左上に実際の room.name を常時表示
//        .overlay(alignment: .topLeading) {
//            Text("room: \(room.name ?? "-")")
//                .font(.caption)
//                .padding(6)
//                .background(Color.black.opacity(0.4))
//                .foregroundColor(.white)
//                .cornerRadius(6)
//                .padding()
//        }
//        // 二重接続防止
//        .task {
//            guard !didStartConnect else { return }
//            didStartConnect = true
//            print("[TASK] connectToRoom start role=\(role == .photographer ? "photographer" : "subject") room=\(roomName)")
//            await connectToRoom(
//                roomName: roomName,
//                identity: role == .photographer ? "photographer" : "subject"
//            )
//        }
//        .onDisappear {
//            Task { await room.disconnect() }
//        }
//        .onChange(of: guideLocked) { locked in
//            print("[STATE] guideLocked -> \(locked)")
//        }
//    }
//
//    // MARK: - ジェスチャ（被写体）
//    private var guideGestures: some Gesture {
//        SimultaneousGesture(
//            DragGesture()
//                .onChanged { v in
//                    guide.offsetX = Double(lastOffset.width + v.translation.width)
//                    guide.offsetY = Double(lastOffset.height + v.translation.height)
//                    Task { await sendGuide(.update) }
//                }
//                .onEnded { _ in
//                    lastOffset = CGSize(width: CGFloat(guide.offsetX), height: CGFloat(guide.offsetY))
//                    print("[GESTURE] drag ended offset=(\(guide.offsetX), \(guide.offsetY))")
//                },
//            MagnificationGesture()
//                .onChanged { value in
//                    guide.scale = Double(lastScale * value)
//                    Task { await sendGuide(.update) }
//                }
//                .onEnded { _ in
//                    lastScale = CGFloat(guide.scale)
//                    print("[GESTURE] magnify ended scale=\(guide.scale)")
//                }
//        )
//    }
//
//    // MARK: - 接続処理
//    @MainActor
//    func connectToRoom(roomName: String, identity: String) async {
//        let tokenURL = "http://192.168.50.233:3000/token?roomName=\(roomName)&identity=\(identity)"
//        guard let url = URL(string: tokenURL) else {
//            print("[CONNECT][ERR] token URL invalid:", tokenURL)
//            return
//        }
//
//        do {
//            print("[TOKEN] GET \(tokenURL)")
//            let (data, _) = try await URLSession.shared.data(from: url)
//
//            if let jsonStr = String(data: data, encoding: .utf8) {
//                print("[TOKEN RAW] \(jsonStr)")
//            }
//
//            let result = try JSONDecoder().decode([String: String].self, from: data)
//            guard let token = result["token"] else { throw URLError(.badServerResponse) }
//            print("[CONNECT] token fetched (len=\(token.count)) for room=\(roomName) identity=\(identity)")
//
//            // 接続前に delegate を登録
//            room.removeAllDelegates()
//
//            // Remote 映像
//            eventProxy.onRemoteVideo = { v in
//                self.remoteTrack = v
//                print("[Proxy->View] remote video set:", v.name)
//            }
//
//            // DataChannel
//            eventProxy.onDataMessage = { data, participant, topic in
//                let fromStr = String(describing: participant?.identity)
//                print("[Proxy->View] onDataMessage bytes=\(data.count) topic=\(topic ?? "(nil)") from=\(fromStr)")
//                self.handleIncomingData(data)
//            }
//
//            // リモート参加者出入り（デバッグ）
//            eventProxy.onRemoteConnected = { (rp: RemoteParticipant) in
//                if let sid = rp.sid {
//                    self.remoteSids.insert(sid)
//                    let idStr = String(describing: rp.identity)
//                    print("[SID] remote connected sid=\(sid) id=\(idStr) sids=\(self.remoteSids)")
//                } else {
//                    let idStr = String(describing: rp.identity)
//                    print("[SID] remote connected (sid=nil) id=\(idStr)")
//                }
//                // 念のためここでも ParticipantDelegate を付与（room delegate 内でも付けている）
//                rp.add(delegate: self.eventProxy)
//            }
//
//            eventProxy.onRemoteDisconnected = { (rp: RemoteParticipant) in
//                if let sid = rp.sid {
//                    self.remoteSids.remove(sid)
//                    let idStr = String(describing: rp.identity)
//                    print("[SID] remote disconnected sid=\(sid) id=\(idStr) sids=\(self.remoteSids)")
//                } else {
//                    let idStr = String(describing: rp.identity)
//                    print("[SID] remote disconnected (sid=nil) id=\(idStr)")
//                }
//            }
//
//            room.add(delegate: eventProxy)
//            print("[CONNECT] Proxy added")
//
//            // 既存のリモート参加者へ ParticipantDelegate を付与（再入室ケースなど）
//            for (_, rp) in room.remoteParticipants {
//                rp.add(delegate: eventProxy)
//                print("[CONNECT] attached ParticipantDelegate to existing:", String(describing: rp.identity))
//            }
//
//            // 接続
//            let connectOptions = ConnectOptions(autoSubscribe: true)
//            try await room.connect(
//                url: "wss://poseguideapp-u7p300v5.livekit.cloud",
//                token: token,
//                connectOptions: connectOptions
//            )
//            print("[CONNECT] connected to room:", String(describing: room.name))
//            isConnected = true
//
//            // 接続完了後も付け直し（堅牢化）
//            for (_, rp) in room.remoteParticipants {
//                rp.add(delegate: eventProxy)
//                print("[CONNECT] re-attached ParticipantDelegate after connect:", String(describing: rp.identity))
//            }
//
//            // 既存公開済みを拾う
//            attachExistingRemoteIfAny()
//
//            // subject は接続完了後に一度現在の状態を送って同期
//            if identity == "subject" {
//                Task { await sendGuide(.update) }
//            }
//
//            // 撮影者のみカメラ publish
//            if identity == "photographer" {
//                try await publishCamera(position: camPos)
//            }
//
//        } catch {
//            print("[CONNECT][ERR] \(error)")
//            errorMessage = "接続に失敗しました"
//        }
//    }
//
//    @MainActor
//    private func attachExistingRemoteIfAny() {
//        for (_, rp) in room.remoteParticipants {
//            for pub in rp.videoTracks {
//                if let t = pub.track as? VideoTrack {
//                    self.remoteTrack = t
//                    print("[REMOTE] attached existing remote video:", t.name, "pub:", pub.sid)
//                    return
//                }
//            }
//        }
//        print("[REMOTE] no existing remote video found")
//    }
//
//    // MARK: - DataChannel 送受信（被写体→撮影者）
//    @MainActor
//    private func sendGuide(_ type: GuideEventType) async {
//        guard role == .subject else { return }
//
//        let msg = GuideMessage(type: type, state: guide, roomName: roomName)
//
//        do {
//            let data = try JSONEncoder().encode(msg)
//
//            // LiveKit iOS 2.8.1: DataPublishOptions はイミュータブル。
//            // 宛先指定(destination)は未対応なので、まずはブロードキャストで確実に届ける。
//            let opt = DataPublishOptions(topic: "guide", reliable: true)
//
//            // デバッグ用に現在のリモート参加者一覧を出す（sid は Optional なので安全に表示）
//            let remoteList = room.remoteParticipants.values.map { rp in
//                let idStr = String(describing: rp.identity)
//                let sidStr = rp.sid.map { "\($0)" } ?? "(nil)"
//                return "[id=\(idStr) sid=\(sidStr)]"
//            }.joined(separator: ", ")
//            print("[SEND] type=\(type) bytes=\(data.count) topic=\(opt.topic ?? "(nil)") reliable=\(opt.reliable) remotes=\(remoteList)")
//
//            try await room.localParticipant.publish(data: data, options: opt)
//            print("[SEND] ok type=\(type)")
//
//            if type == .lock {
//                guideLocked = true
//                print("[SEND] local guideLocked set true (subject)")
//            }
//        } catch {
//            print("[SEND][ERR] \(error)")
//        }
//    }
//
//
//
//    @MainActor
//    private func handleIncomingData(_ data: Data) {
//        print("[RECV] raw bytes=\(data.count)")
//
//        // ★ まず“届いたか”だけ確認：届いたら即ロック表示
//        if role == .photographer {
//            self.guideLocked = true
//        }
//
//        do {
//            let msg = try JSONDecoder().decode(GuideMessage.self, from: data)
//            print("[RECV] decoded type=\(msg.type) room=\(msg.roomName)")
//            if role == .photographer {
//                self.guide = msg.state
//                if msg.type == .lock {
//                    self.guideLocked = true
//                    print("[RECV] guide locked by subject -> guideLocked=true")
//                }
//            } else {
//                print("[RECV] message on subject side (ignored)")
//            }
//        } catch {
//            print("[RECV][ERR] decode failed:", error.localizedDescription)
//        }
//    }
//
//
//
//    // MARK: - カメラ制御（撮影者）
//    @MainActor
//    private func publishCamera(position: CamPos) async throws {
//        if let track = localTrack,
//           let capturer = track.capturer as? CameraCapturer {
//            try await capturer.set(cameraPosition: position == .front ? .front : .back)
//            camPos = position
//            print("[CAMERA] switched (reuse track): \(position == .front ? "front" : "back")")
//            return
//        }
//
//        let options = CameraCaptureOptions(position: position == .front ? .front : .back)
//        let cam = LocalVideoTrack.createCameraTrack(options: options)
//        self.localTrack = cam
//        let pub: LocalTrackPublication = try await room.localParticipant.publish(videoTrack: cam)
//        self.localPub = pub
//        camPos = position
//        print("[CAMERA] published video (\(position == .front ? "front" : "back"))")
//    }
//
//    @MainActor
//    private func switchCamera(_ to: CamPos) async {
//        guard role == .photographer else { return }
//        if camPos == to { return }
//        do {
//            if let track = localTrack,
//               let capturer = track.capturer as? CameraCapturer {
//                try await capturer.set(cameraPosition: to == .front ? .front : .back)
//                camPos = to
//                print("[CAMERA] set position -> \(to == .front ? "front" : "back")")
//            } else {
//                try await publishCamera(position: to)
//            }
//        } catch {
//            print("[CAMERA][ERR] \(error)")
//            self.errorMessage = "カメラ切替に失敗しました"
//        }
//    }
//
//    // 撮影（撮影者・確定後のみ）
//    @MainActor
//    private func captureAndSaveCurrentFrame() async {
//        guard role == .photographer, guideLocked else {
//            print("[SNAPSHOT] guard failed role=\(role == .photographer ? "photographer" : "subject") locked=\(guideLocked)")
//            return
//        }
//
//        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
//        if status == .notDetermined {
//            print("[SNAPSHOT] request photo addOnly permission")
//            _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
//        }
//        guard PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized else {
//            print("[SNAPSHOT][ERR] not authorized for addOnly")
//            self.errorMessage = "写真への保存が許可されていません（設定で許可してください）"
//            return
//        }
//
//        let renderer = ImageRenderer(content: snapshotContentView)
//        renderer.scale = UIScreen.main.scale
//
//        if let uiImage = renderer.uiImage {
//            PHPhotoLibrary.shared().performChanges({
//                PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
//            }) { success, err in
//                Task { @MainActor in
//                    if success {
//                        print("[SNAPSHOT] saved to library")
//                    } else {
//                        print("[SNAPSHOT][ERR] \(err?.localizedDescription ?? "unknown")")
//                        self.errorMessage = "保存に失敗しました"
//                    }
//                }
//            }
//        } else {
//            print("[SNAPSHOT][ERR] renderer.uiImage nil")
//            self.errorMessage = "撮影に失敗しました"
//        }
//    }
//
//    @ViewBuilder
//    private var snapshotContentView: some View {
//        ZStack {
//            if role == .subject, let t = remoteTrack {
//                LKVideoView(track: t, contentMode: .scaleAspectFit)
//            } else if role == .photographer, let lt = localTrack {
//                LKVideoView(track: lt, contentMode: .scaleAspectFit)
//            } else { Color.black }
//
//            if let frame = guideFrame {
//                Image(uiImage: frame)
//                    .resizable()
//                    .scaledToFit()
//                    .scaleEffect(CGFloat(guide.scale))
//                    .opacity(guide.opacity)
//                    .offset(x: CGFloat(guide.offsetX), y: CGFloat(guide.offsetY))
//        }
//        }
//        .frame(maxWidth: .infinity, maxHeight: .infinity)
//        .ignoresSafeArea()
//    }
//}

import SwiftUI
import LiveKit
import Photos

struct LiveRoomView: View {
    let role: UserRole
    let roomName: String

    @StateObject private var room = Room()

    @State private var isConnected = false
    @State private var errorMessage: String?

    // 強参照保持（超重要：connect 中に委譲が解放されないようにする）
    @State private var simpleDelegate: SimpleRoomDelegate?

    // 映像
    @State private var remoteTrack: VideoTrack?
    @State private var localTrack: LocalVideoTrack?

    // ガイド（最小：不透明度だけ）
    @State private var guide = GuideState()
    @State private var guideImage: UIImage? = UIImage(named: "pose_guide1_silhouette")

    // カメラ（撮影者のみ）
    enum CamPos { case front, back }
    @State private var camPos: CamPos = .front

    // 二重接続防止
    @State private var didStartConnect = false

    var body: some View {
        ZStack {
            // ==== 映像レイヤー ====
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
                Color.gray.opacity(0.2).ignoresSafeArea()
                    .overlay(Text("接続中..."))
            }

            // ==== ガイド（両者に同じ画像を重ねる・同期なしの最小デモ） ====
            if let ui = guideImage {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .opacity(guide.opacity)
                    .padding()
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.15), value: guide.opacity)
            }

            // ==== 共通：ガイド不透明度スライダー ====
            VStack {
                Spacer()
                HStack {
                    Image(systemName: "square.stack.3d.down.forward")
                    Slider(value: Binding(
                        get: { guide.opacity },
                        set: { guide.opacity = min(1.0, max(0.0, $0)) }
                    ), in: 0...1, step: 0.01)
                    Text(String(format: "%.0f%%", guide.opacity * 100))
                        .monospacedDigit()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, role == .photographer ? 120 : 24)
            }
            .padding(.horizontal)

            // ==== 撮影者 UI：右下カメラ切替 & 下中央シャッター ====
            if role == .photographer {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            Task { await switchCamera(camPos == .front ? .back : .front) }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(width: 56, height: 56)
                                .background(.white)
                                .clipShape(Circle())
                                .shadow(radius: 6, y: 2)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 110)
                    }
                }
                .ignoresSafeArea()

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

            if let errorMessage {
                VStack { Spacer(); Text(errorMessage).foregroundColor(.red).padding() }
            }
        }
        // 左上に room.name（サーバが返した実名）を表示
        .overlay(alignment: .topLeading) {
            Text("room: \(room.name ?? "-")")
                .font(.caption2)
                .padding(6)
                .background(Color.black.opacity(0.35))
                .foregroundColor(.white)
                .cornerRadius(6)
                .padding()
        }
        .task {
            guard !didStartConnect else { return }
            didStartConnect = true
            await connectToRoom(roomName: roomName, identity: role == .photographer ? "photographer" : "subject")
        }
        .onDisappear {
            Task { await room.disconnect() }
        }
    }

    // MARK: - 接続
    @MainActor
    private func connectToRoom(roomName: String, identity: String) async {
        let tokenURL = "http://192.168.50.233:3000/token?roomName=\(roomName)&identity=\(identity)"
        guard let url = URL(string: tokenURL) else {
            errorMessage = "トークン URL が不正です"
            return
        }

        do {
            print("[TOKEN] GET \(tokenURL)")
            let (data, _) = try await URLSession.shared.data(from: url)
            if let raw = String(data: data, encoding: .utf8) { print("[TOKEN RAW] \(raw)") }
            let json = try JSONDecoder().decode([String: String].self, from: data)
            guard let token = json["token"] else { throw URLError(.badServerResponse) }

            // 1) connect 前に delegate を add（＆強参照保持）
            room.removeAllDelegates()
            let delegate = SimpleRoomDelegate { v in
                Task { @MainActor in
                    self.remoteTrack = v
                    print("[VIEW] remote track set:", v.name)
                }
            }
            room.add(delegate: delegate)
            self.simpleDelegate = delegate
            print("[CONNECT] Proxy added")

            // 2) 接続（被写体は autoSubscribe: true で自動購読）
            try await room.connect(
                url: "wss://poseguideapp-u7p300v5.livekit.cloud",
                token: token,
                connectOptions: ConnectOptions(autoSubscribe: true)
            )
            isConnected = true
            print("[CONNECT] connected to room:", room.name ?? "-")

            // 3) 既存のトラックを拾う（接続順で取れないことがあるため）
            attachExistingRemoteIfAny()

            // 4) 撮影者のみカメラ publish（1度だけ）
            if identity == "photographer" {
                try await publishCamera(position: camPos)
            }

        } catch {
            print("[CONNECT][ERR]", error.localizedDescription)
            errorMessage = "接続に失敗しました"
        }
    }

    @MainActor
    private func attachExistingRemoteIfAny() {
        var picked = false
        for (_, rp) in room.remoteParticipants {
            for pub in rp.videoTracks {
                if let t = pub.track as? VideoTrack {
                    self.remoteTrack = t
                    print("[REMOTE] attached existing:", t.name, "pub:", pub.sid, "from:", rp.identity ?? "(nil)")
                    picked = true
                    break
                }
            }
            if picked { break }
        }
        if !picked { print("[REMOTE] no existing remote video found") }
    }

    // MARK: - カメラ制御（撮影者）
    @MainActor
    private func publishCamera(position: CamPos) async throws {
        if localTrack == nil {
            let options = CameraCaptureOptions(position: position == .front ? .front : .back)
            let cam = LocalVideoTrack.createCameraTrack(options: options)
            self.localTrack = cam
            _ = try await room.localParticipant.publish(videoTrack: cam)
            print("[CAMERA] published video (\(position == .front ? "front" : "back"))")
        }
    }

    @MainActor
    private func switchCamera(_ to: CamPos) async {
        guard role == .photographer else { return }
        do {
            if let track = localTrack,
               let capturer = track.capturer as? CameraCapturer {
                try await capturer.set(cameraPosition: to == .front ? .front : .back)
                camPos = to
                print("[CAMERA] switched -> \(to == .front ? "front" : "back")")
            } else {
                try await publishCamera(position: to)
                camPos = to
            }
        } catch {
            print("[CAMERA][ERR]", error.localizedDescription)
            self.errorMessage = "カメラ切替に失敗しました"
        }
    }

    // MARK: - シャッター（撮影者）
    @MainActor
    private func captureAndSaveCurrentFrame() async {
        guard role == .photographer else { return }

        // 写真保存の権限
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized else {
            self.errorMessage = "写真の保存が許可されていません（設定で許可してください）"
            return
        }

        // レンダリング（画面と同じ重なりで保存）
        let renderer = ImageRenderer(content: snapshotView)
        renderer.scale = UIScreen.main.scale

        if let image = renderer.uiImage {
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, err in
                Task { @MainActor in
                    if success {
                        print("[SNAPSHOT] saved")
                    } else {
                        self.errorMessage = "保存に失敗しました"
                        print("[SNAPSHOT][ERR]", err?.localizedDescription ?? "unknown")
                    }
                }
            }
        } else {
            self.errorMessage = "撮影に失敗しました"
        }
    }

    @ViewBuilder
    private var snapshotView: some View {
        ZStack {
            if role == .subject, let t = remoteTrack {
                LKVideoView(track: t, contentMode: .scaleAspectFit)
            } else if role == .photographer, let lt = localTrack {
                LKVideoView(track: lt, contentMode: .scaleAspectFit)
            } else {
                Color.black
            }
            if let ui = guideImage {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .opacity(guide.opacity)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}
