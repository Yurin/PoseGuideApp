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

// UIKit の LiveKit.VideoView を SwiftUI で使い、実体参照を保持するラッパ
struct VideoViewContainer: UIViewRepresentable {
    let track: VideoTrack
    let contentMode: UIView.ContentMode

    final class RefBox { weak var view: VideoView? }
    let refBox: RefBox

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.isOpaque = true
        host.backgroundColor = .black
        host.layer.masksToBounds = false

        let v = VideoView()
        v.isOpaque = true
        v.backgroundColor = .black
        v.layer.masksToBounds = false
        v.contentMode = contentMode
        v.track = track

        v.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: host.topAnchor),
            v.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: host.trailingAnchor)
        ])

        refBox.view = v
        return host
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let v = refBox.view {
            v.track = track
            v.contentMode = contentMode
        }
    }
}

struct LiveRoomView: View {
    enum UserRole { case photographer, subject }

    let role: UserRole
    let roomName: String

    @StateObject private var room = Room()
    @State private var isConnected = false
    @State private var errorMessage: String?

    // 最小限：ビデオ
    @State private var remoteTrack: VideoTrack?
    @State private var localTrack: LocalVideoTrack?

    // ガイド（既存の GuideState.swift を使用：opacity / scale / offsetX / offsetY）
    @State private var guideImage: UIImage? = UIImage(named: "pose_guide1_silhouette")
    @State private var guide = GuideState()

    // スナップショット用：VideoView 実体への参照
    private let videoRefBox = VideoViewContainer.RefBox()

    // カメラ向き
    enum CamPos { case front, back }
    @State private var camPos: CamPos = .front

    var body: some View {
        ZStack {
            if isConnected {
                if role == .subject, let t = remoteTrack {
                    VideoHost(track: t).ignoresSafeArea()
                } else if role == .photographer, let lt = localTrack {
                    VideoHostLocal(track: lt).ignoresSafeArea()
                } else {
                    Color.black.overlay(Text("映像を待っています").foregroundColor(.white))
                }
            } else {
                Color.gray.opacity(0.2).overlay(Text("接続中..."))
            }

            // ---- ガイド（両者で同じものを見る／今回は不透明度のみ調整可）----
            if let gimg = guideImage {
                Image(uiImage: gimg)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(guide.scale)
                    .offset(x: CGFloat(guide.offsetX), y: CGFloat(guide.offsetY))
                    .opacity(guide.opacity)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.15), value: guide.opacity)
            }

            // ---- 下部 UI ----
            VStack {
                Spacer()
                HStack {
                    // 不透明度スライダー（両者とも操作可）
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ガイド不透明度 \(String(format: "%.2f", guide.opacity))")
                            .font(.caption)
                            .foregroundColor(.white)
                        Slider(value: Binding(get: { guide.opacity },
                                              set: { guide.opacity = $0 }),
                               in: 0...1)
                            .frame(width: 220)
                    }
                    .padding(12)
                    .background(.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.leading, 16)

                    Spacer()

                    if role == .photographer {
                        HStack(spacing: 12) {
                            Button {
                                Task { await switchCamera(camPos == .front ? .back : .front) }
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath.camera")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.black)
                                    .frame(width: 44, height: 44)
                                    .background(.white)
                                    .clipShape(Circle())
                                    .shadow(radius: 4, y: 2)
                            }

                            Button {
                                Task { await captureAndSaveCurrentFrame() }
                            } label: {
                                ZStack {
                                    Circle().fill(Color.white.opacity(0.95)).frame(width: 64, height: 64)
                                    Circle().stroke(Color.white, lineWidth: 3).frame(width: 76, height: 76)
                                }
                            }
                        }
                        .padding(.trailing, 16)
                    }
                }
                .padding(.bottom, 20)
            }

            if let errorMessage {
                VStack { Spacer(); Text(errorMessage).foregroundColor(.red).padding() }
            }
        }
        .overlay(alignment: .topLeading) {
            Text("room: \(room.name ?? "-")")
                .font(.caption2)
                .foregroundColor(.white)
                .padding(6)
                .background(.black.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(8)
        }
        .task {
            await connectToRoom(roomName: roomName,
                                identity: role == .photographer ? "photographer" : "subject")
        }
        .onDisappear { Task { await room.disconnect() } }
    }

    @ViewBuilder
    private func VideoHost(track: VideoTrack) -> some View {
        VideoViewContainer(track: track,
                           contentMode: .scaleAspectFit,
                           refBox: videoRefBox)
    }

    @ViewBuilder
    private func VideoHostLocal(track: LocalVideoTrack) -> some View {
        // LocalVideoTrack は VideoTrack を継承
        VideoViewContainer(track: track,
                           contentMode: .scaleAspectFit,
                           refBox: videoRefBox)
    }

    // MARK: - 接続（最小）
    private func connectToRoom(roomName: String, identity: String) async {
        let tokenURL = "http://192.168.50.233:3000/token?roomName=\(roomName)&identity=\(identity)"
        guard let url = URL(string: tokenURL) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try JSONDecoder().decode([String: String].self, from: data)
            guard let token = result["token"] else { throw URLError(.badServerResponse) }

            // リモートの映像購読だけ拾うデリゲート
            room.removeAllDelegates()
            let del = SimpleRoomDelegate { v in self.remoteTrack = v }
            room.add(delegate: del)

            let connectOptions = ConnectOptions(autoSubscribe: true)
            try await room.connect(
                url: "wss://poseguideapp-u7p300v5.livekit.cloud",
                token: token,
                connectOptions: connectOptions
            )
            isConnected = true

            if identity == "photographer" {
                try await publishCamera(position: camPos)
            } else {
                attachExistingRemoteIfAny()
            }
        } catch {
            print("[CONNECT][ERR] \(error)")
            self.errorMessage = "接続に失敗しました"
        }
    }

    private func attachExistingRemoteIfAny() {
        for (_, rp) in room.remoteParticipants {
            for pub in rp.videoTracks {
                if let t = pub.track as? VideoTrack {
                    self.remoteTrack = t
                    return
                }
            }
        }
    }

    // MARK: - カメラ
    private func publishCamera(position: CamPos) async throws {
        if let track = localTrack,
           let capturer = track.capturer as? CameraCapturer {
            try await capturer.set(cameraPosition: position == .front ? .front : .back)
            camPos = position
            return
        }
        let options = CameraCaptureOptions(position: position == .front ? .front : .back)
        let cam = LocalVideoTrack.createCameraTrack(options: options)
        self.localTrack = cam
        _ = try await room.localParticipant.publish(videoTrack: cam)
        camPos = position
    }

    private func switchCamera(_ to: CamPos) async {
        do {
            try await publishCamera(position: to)
        } catch {
            self.errorMessage = "カメラ切替に失敗しました"
        }
    }

    // MARK: - 撮影（ガイド抜きで VideoView だけ保存）
    private func captureAndSaveCurrentFrame() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized else {
            self.errorMessage = "写真への保存が許可されていません（設定で許可してください）"
            return
        }

        guard let videoView = videoRefBox.view else {
            self.errorMessage = "映像ビューが見つかりません"
            return
        }

        videoView.layoutIfNeeded()

        let targetSize = videoView.bounds.size
        guard targetSize.width > 0, targetSize.height > 0 else {
            self.errorMessage = "映像ビューのサイズが不正です"
            return
        }

        let scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: {
            let f = UIGraphicsImageRendererFormat()
            f.scale = scale
            f.opaque = true
            return f
        }())

        let image = renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.black.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: targetSize))
            videoView.layer.render(in: ctx.cgContext) // ガイドは含まれない
        }

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, err in
            DispatchQueue.main.async {
                if !success {
                    self.errorMessage = "保存に失敗しました: \(err?.localizedDescription ?? "unknown")"
                }
            }
        }
    }
}
