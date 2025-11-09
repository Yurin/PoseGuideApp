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
import AVFoundation
import Photos

// ===== LiveKit の VideoView(UIKit) を SwiftUI で使うためのラッパ =====
struct VideoHostView: UIViewRepresentable {
    let track: VideoTrack?
    let contentMode: UIView.ContentMode

    func makeUIView(context: Context) -> LiveKit.VideoView {
        let v = LiveKit.VideoView()
        v.contentMode = contentMode
        v.track = track
        v.clipsToBounds = true
        return v
    }

    func updateUIView(_ uiView: LiveKit.VideoView, context: Context) {
        uiView.contentMode = contentMode
        uiView.track = track
    }
}

// ===== ガイド無しで 1 枚だけ生写真を撮って UIImage を返す最小キャプチャ =====
final class SingleShotCapturer: NSObject, AVCapturePhotoCaptureDelegate {
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var completion: ((UIImage?) -> Void)?

    func capture(prefer position: AVCaptureDevice.Position, completion: @escaping (UIImage?) -> Void) {
        self.completion = completion

        session.beginConfiguration()
        session.sessionPreset = .photo

        // ← ここを default(_:for:position:) に修正
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            completion(nil)
            return
        }
        session.addInput(input)

        guard session.canAddOutput(output) else {
            session.commitConfiguration(); completion(nil); return
        }
        session.addOutput(output)
        output.isHighResolutionCaptureEnabled = true

        session.commitConfiguration()

        let queue = DispatchQueue(label: "single-shot")
        queue.async {
            self.session.startRunning()
            usleep(200_000) // 0.2sだけ安定待ち
            let settings = AVCapturePhotoSettings()
            settings.isHighResolutionPhotoEnabled = true
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        session.stopRunning()
        if let error = error {
            print("[AVCapture][ERR]", error.localizedDescription)
            completion?(nil); completion = nil
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            completion?(nil); completion = nil
            return
        }
        completion?(image); completion = nil
    }
}

// ===== ここから本体 =====
struct LiveRoomView: View {

    enum UserRole { case photographer, subject }
    let role: UserRole
    let roomName: String

    // LiveKit
    @StateObject private var room = Room()
    @State private var isConnected = false
    @State private var errorMessage: String?

    // 映像
    @State private var remoteTrack: VideoTrack?
    @State private var localTrack: LocalVideoTrack?
    @State private var localPub: LocalTrackPublication?

    // カメラ向き
    enum CamPos { case front, back }
    @State private var camPos: CamPos = .front

    // ガイド（不透明度のみ調整）
    @State private var guideImage: UIImage? = UIImage(named: "pose_guide1_silhouette")
    @State private var guide = GuideState() // opacity を利用

    // 生写真キャプチャ
    private let singleShot = SingleShotCapturer()

    var body: some View {
        ZStack {
            // ===== 映像レイヤ =====
            if isConnected {
                if role == .photographer, let lt = localTrack {
                    VideoHostView(track: lt, contentMode: .scaleAspectFit)
                        .ignoresSafeArea()
                } else if role == .subject, let rt = remoteTrack {
                    VideoHostView(track: rt, contentMode: .scaleAspectFit)
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                        .overlay(Text("映像を待っています").foregroundColor(.white))
                }
            } else {
                Color.gray.opacity(0.3).ignoresSafeArea()
                    .overlay(Text("接続中...").foregroundColor(.black))
            }

            // ===== ガイド重畳（両者に表示・不透明度だけ調整可） =====
            if let g = guideImage {
                Image(uiImage: g)
                    .resizable()
                    .scaledToFit()
                    .opacity(guide.opacity)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.15), value: guide.opacity)
            }

            // ===== 下部：ガイド不透明度スライダ（両者） =====
            VStack {
                Spacer()
                HStack {
                    Image(systemName: "square.on.square.dashed")
                    Slider(value: Binding(get: {
                        guide.opacity
                    }, set: { v in
                        guide.opacity = v
                    }), in: 0.0...1.0)
                    .frame(maxWidth: 240)
                    Text(String(format: "%.0f%%", guide.opacity * 100))
                        .monospacedDigit()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.bottom, role == .photographer ? 110 : 24)
            }
            .ignoresSafeArea()

            // ===== 撮影者 UI：カメラ切替＋シャッター =====
            if role == .photographer {
                // 右下：カメラ切替
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
                        .padding(.bottom, 110)
                    }
                }
                .ignoresSafeArea()

                // 下中央：シャッター（ガイド無し保存）
                VStack {
                    Spacer()
                    Button {
                        Task { await captureWithAVFoundation() }
                    } label: {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.92)).frame(width: 72, height: 72)
                            Circle().stroke(Color.white, lineWidth: 3).frame(width: 84, height: 84)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .ignoresSafeArea()
            }

            if let errorMessage {
                VStack { Spacer(); Text(errorMessage).foregroundColor(.red).padding() }
            }
        }
        .overlay(alignment: .topLeading) {
            Text("room: \(room.name ?? "-")")
                .font(.caption)
                .padding(6)
                .background(Color.black.opacity(0.4))
                .foregroundColor(.white)
                .cornerRadius(6)
                .padding()
        }
        .task {
            await connectToRoom(
                roomName: roomName,
                identity: (role == .photographer ? "photographer" : "subject")
            )
        }
        .onDisappear {
            Task { await room.disconnect() }
        }
    }

    // ===== 最小デリゲート（購読時に VideoTrack を拾うだけ） =====
    final class MinimalRoomDelegate: NSObject, RoomDelegate {
        private let onVideo: (VideoTrack) -> Void
        init(onVideo: @escaping (VideoTrack) -> Void) {
            self.onVideo = onVideo
        }
        func room(_ room: Room,
                  participant: RemoteParticipant,
                  didSubscribeTrack publication: RemoteTrackPublication,
                  track: Track) {
            if let v = track as? VideoTrack { onVideo(v) }
        }
    }

    // ===== 接続 =====
    @MainActor
    private func connectToRoom(roomName: String, identity: String) async {
        let tokenURL = "http://172.30.57.208:3000/token?roomName=\(roomName)&identity=\(identity)"
        guard let url = URL(string: tokenURL) else {
            print("[CONNECT][ERR] token URL invalid:", tokenURL); return
        }

        do {
            print("[TOKEN] GET \(tokenURL)")
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try JSONDecoder().decode([String: String].self, from: data)
            guard let token = result["token"] else { throw URLError(.badServerResponse) }
            print("[CONNECT] token fetched (len=\(token.count)) for room=\(roomName) identity=\(identity)")

            room.removeAllDelegates()
            let delegate = MinimalRoomDelegate { v in
                self.remoteTrack = v
                print("[DELEGATE] subscribed remote video")
            }
            room.add(delegate: delegate)

            let connectOptions = ConnectOptions(autoSubscribe: true)
            try await room.connect(
                url: "wss://poseguideapp-u7p300v5.livekit.cloud",
                token: token,
                connectOptions: connectOptions
            )
            isConnected = true
            print("[CONNECT] connected to room:", room.name ?? "(nil)")

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

    @MainActor
    private func attachExistingRemoteIfAny() {
        for (_, rp) in room.remoteParticipants {
            for pub in rp.videoTracks {
                if let t = pub.track as? VideoTrack {
                    self.remoteTrack = t
                    print("[REMOTE] attached existing remote video:", t.name, "pub:", pub.sid)
                    return
                }
            }
        }
        print("[REMOTE] no existing remote video found")
    }

    // ===== カメラ =====
    @MainActor
    private func publishCamera(position: CamPos) async throws {
        if let track = localTrack,
           let capturer = track.capturer as? CameraCapturer {
            try await capturer.set(cameraPosition: position == .front ? .front : .back)
            camPos = position
            print("[CAMERA] switched (reuse track): \(position == .front ? "front" : "back")")
            return
        }

        let options = CameraCaptureOptions(position: position == .front ? .front : .back)
        let cam = LocalVideoTrack.createCameraTrack(options: options)
        self.localTrack = cam
        let pub: LocalTrackPublication = try await room.localParticipant.publish(videoTrack: cam)
        self.localPub = pub
        camPos = position
        print("[CAMERA] published video (\(position == .front ? "front" : "back"))")
    }

    @MainActor
    private func switchCamera(_ to: CamPos) async {
        guard role == .photographer else { return }
        if camPos == to { return }
        do {
            if let track = localTrack,
               let capturer = track.capturer as? CameraCapturer {
                try await capturer.set(cameraPosition: to == .front ? .front : .back)
                camPos = to
                print("[CAMERA] set position -> \(to == .front ? "front" : "back")")
            } else {
                try await publishCamera(position: to)
            }
        } catch {
            print("[CAMERA][ERR] \(error)")
            self.errorMessage = "カメラ切替に失敗しました"
        }
    }

    // ===== 撮影（ガイド無しを写真ライブラリへ） =====
    @MainActor
    private func captureWithAVFoundation() async {
        guard role == .photographer else { return }

        // 追加専用の権限
        if PHPhotoLibrary.authorizationStatus(for: .addOnly) == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized else {
            self.errorMessage = "写真への保存が許可されていません（設定で許可してください）"
            return
        }

        // 1) LiveKit 側カメラを一時停止
        let resumePos: CamPos = camPos
        if let track = localTrack, let capturer = track.capturer as? CameraCapturer {
            do {
                try await capturer.stopCapture()
                try? await Task.sleep(nanoseconds: 150_000_000)
            } catch {
                print("[SHOT] stopCapture error: \(error)")
            }
        }

        // 2) AVFoundation で生写真を1枚撮影
        let prefer: AVCaptureDevice.Position = (resumePos == .front) ? .front : .back

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            singleShot.capture(prefer: prefer) { image in
                if let img = image {
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAsset(from: img)
                    }) { success, err in
                        DispatchQueue.main.async {
                            if success { print("[SHOT] saved to library") }
                            else {
                                self.errorMessage = "保存に失敗しました"
                                print("[SHOT][ERR] \(err?.localizedDescription ?? "unknown")")
                            }
                            cont.resume()
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.errorMessage = "撮影に失敗しました"
                        cont.resume()
                    }
                }
            }
        }

        // 3) LiveKit のカメラを再開
        if let track = localTrack, let capturer = track.capturer as? CameraCapturer {
            do {
                try await capturer.startCapture()
                try await capturer.set(cameraPosition: (resumePos == .front ? .front : .back))
                print("[SHOT] camera restarted (\(resumePos == .front ? "front" : "back"))")
            } catch {
                print("[SHOT][ERR] restart failed: \(error)")
            }
        }
    }
}
