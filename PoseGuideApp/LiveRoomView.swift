//import SwiftUI
//import LiveKit
//import AVFoundation
//import Photos
//
//// ===== LiveKit の VideoView(UIKit) を SwiftUI で使うためのラッパ =====
//struct VideoHostView: UIViewRepresentable {
//    let track: VideoTrack?
//    let contentMode: UIView.ContentMode
//
//    func makeUIView(context: Context) -> LiveKit.VideoView {
//        let v = LiveKit.VideoView()
//        v.contentMode = contentMode
//        v.track = track
//        v.clipsToBounds = true
//        return v
//    }
//
//    func updateUIView(_ uiView: LiveKit.VideoView, context: Context) {
//        uiView.contentMode = contentMode
//        uiView.track = track
//    }
//}
//
//// ===== ガイド無しで 1 枚だけ生写真を撮って UIImage を返す最小キャプチャ =====
//final class SingleShotCapturer: NSObject, AVCapturePhotoCaptureDelegate {
//    private let session = AVCaptureSession()
//    private let output = AVCapturePhotoOutput()
//    private var completion: ((UIImage?) -> Void)?
//
//    func capture(prefer position: AVCaptureDevice.Position, completion: @escaping (UIImage?) -> Void) {
//        self.completion = completion
//
//        session.beginConfiguration()
//        session.sessionPreset = .photo
//
//        guard
//            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
//            let input = try? AVCaptureDeviceInput(device: device),
//            session.canAddInput(input)
//        else {
//            session.commitConfiguration()
//            completion(nil)
//            return
//        }
//        session.addInput(input)
//
//        guard session.canAddOutput(output) else {
//            session.commitConfiguration()
//            completion(nil)
//            return
//        }
//        session.addOutput(output)
//        output.isHighResolutionCaptureEnabled = true
//
//        session.commitConfiguration()
//
//        let queue = DispatchQueue(label: "single-shot")
//        queue.async {
//            self.session.startRunning()
//            usleep(200_000) // 0.2sだけ安定待ち
//            let settings = AVCapturePhotoSettings()
//            settings.isHighResolutionPhotoEnabled = true
//            self.output.capturePhoto(with: settings, delegate: self)
//        }
//    }
//
//    func photoOutput(_ output: AVCapturePhotoOutput,
//                     didFinishProcessingPhoto photo: AVCapturePhoto,
//                     error: Error?) {
//        session.stopRunning()
//        if let error = error {
//            print("[AVCapture][ERR]", error.localizedDescription)
//            completion?(nil); completion = nil
//            return
//        }
//        guard let data = photo.fileDataRepresentation(),
//              let image = UIImage(data: data) else {
//            completion?(nil); completion = nil
//            return
//        }
//        completion?(image); completion = nil
//    }
//}
//
//// ===== 同期用モデル =====
//struct GuideTransform: Codable, Equatable {
//    var scale: CGFloat = 1.0
//    var offsetX: CGFloat = 0.0
//    var offsetY: CGFloat = 0.0
//    var rotation: CGFloat = 0.0 // ラジアン
//}
//
//struct GuidePayload: Codable, Equatable {
//    var index: Int
//    var transform: GuideTransform
//}
//
//// ===== ここから本体 =====
//struct LiveRoomView: View {
//
//    enum UserRole { case photographer, subject }
//    let role: UserRole
//    let roomName: String
//
//    // LiveKit
//    @StateObject private var room = Room()
//    @State private var isConnected = false
//    @State private var errorMessage: String?
//    @State private var roomDelegate: MinimalRoomDelegate? // 強参照保持が必須
//
//    // 映像
//    @State private var remoteTrack: VideoTrack?
//    @State private var localTrack: LocalVideoTrack?
//    @State private var localPub: LocalTrackPublication?
//
//    // カメラ向き
//    enum CamPos { case front, back }
//    @State private var camPos: CamPos = .front
//
//    // データチャンネル
//    private let guideTopic = "guide-sync"
//
//    // 被写体が選ぶサムネ（写真）
//    private let photoAssets = [
//        "pose_guide1",
//        "pose_guide2",
//        "pose_guide3",
//        "pose_guide4"
//    ]
//
//    // 実際に重ねるフレーム（シルエット）
//    private let frameAssets = [
//        "pose_guide1_silhouette",
//        "pose_guide2_silhouette",
//        "pose_guide3_silhouette",
//        "pose_guide4_silhouette"
//    ]
//
//    @State private var selectedGuideIndex: Int = 0
//    @State private var guideImage: UIImage? = UIImage(named: "pose_guide1_silhouette")
//
//    // 透過度（両者共通UI・上固定）
//    @State private var guideOpacity: CGFloat = 1.0
//
//    // ガイド変形（確定前の作業用と確定後の本体を分離）
//    @State private var baseTransform = GuideTransform()       // 確定済みの基準
//    @State private var workScale: CGFloat = 1.0               // ジェスチャ中の一時値
//    @State private var workOffset: CGSize = .zero
//    @State private var workRotation: Angle = .zero
//
//    // 被写体 UI
//    @State private var showGuidePicker = false
//    @State private var showSentToast = false
//
//    // 受信ログの簡易表示（撮影者側だけ）
//    @State private var lastRxLog: String = "-"
//
//    // 生写真キャプチャ
//    private let singleShot = SingleShotCapturer()
//
//    // 現在の見た目に効く合成変形
//    private var effScale: CGFloat { baseTransform.scale * workScale }
//    private var effRotation: Angle { Angle(radians: Double(baseTransform.rotation)) + workRotation }
//    private var effOffset: CGSize {
//        CGSize(width: baseTransform.offsetX + workOffset.width,
//               height: baseTransform.offsetY + workOffset.height)
//    }
//
//    // 現在の確定すべき状態
//    private var currentEffectiveTransform: GuideTransform {
//        var t = baseTransform
//        t.scale *= workScale
//        t.offsetX += workOffset.width
//        t.offsetY += workOffset.height
//        t.rotation += CGFloat(workRotation.radians)
//        return t
//    }
//
//    var body: some View {
//        ZStack {
//            // ===== 映像レイヤ =====
//            if isConnected {
//                if role == .photographer, let lt = localTrack {
//                    VideoHostView(track: lt, contentMode: .scaleAspectFit)
//                        .ignoresSafeArea()
//                } else if role == .subject, let rt = remoteTrack {
//                    VideoHostView(track: rt, contentMode: .scaleAspectFit)
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
//            // ===== ガイド重畳（両者に表示） =====
//            if let g = guideImage {
//                Image(uiImage: g)
//                    .resizable()
//                    .scaledToFit()
//                    .opacity(guideOpacity)
//                    .scaleEffect(effScale)
//                    .rotationEffect(effRotation)
//                    .offset(effOffset)
//                    .allowsHitTesting(role == .subject) // 被写体のみ操作可
//                    .gesture(role == .subject ? subjectTransformGestures() : nil)
//            }
//
//            // ===== 撮影者 UI：カメラ切替＋シャッター =====
//            if role == .photographer {
//                // 右下：カメラ切替
//                VStack {
//                    Spacer()
//                    HStack {
//                        Spacer()
//                        Button {
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
//                        .padding(.bottom, 120)
//                    }
//                }
//                .ignoresSafeArea()
//
//                // 下中央：シャッター（ガイド無し保存）
//                VStack {
//                    Spacer()
//                    Button {
//                        Task { await captureWithAVFoundation() }
//                    } label: {
//                        ZStack {
//                            Circle().fill(Color.white.opacity(0.92)).frame(width: 72, height: 72)
//                            Circle().stroke(Color.white, lineWidth: 3).frame(width: 84, height: 84)
//                        }
//                    }
//                    .padding(.bottom, 24)
//                }
//                .ignoresSafeArea()
//            }
//
//            // ===== 被写体 UI：左下に「選択トグル」、右下に「確定」 =====
//            if role == .subject {
//                VStack {
//                    Spacer()
//                    HStack {
//                        // 左下：トグル
//                        Button {
//                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
//                                showGuidePicker.toggle()
//                            }
//                        } label: {
//                            Image(systemName: "photo.on.rectangle")
//                                .font(.system(size: 18, weight: .semibold))
//                                .foregroundColor(.black)
//                                .frame(width: 48, height: 48)
//                                .background(.white)
//                                .clipShape(Circle())
//                                .shadow(radius: 6, y: 2)
//                                .overlay(
//                                    Group {
//                                        if showGuidePicker {
//                                            Circle().stroke(Color.blue, lineWidth: 2)
//                                        }
//                                    }
//                                )
//                        }
//                        .padding(.leading, 20)
//
//                        Spacer()
//
//                        // 右下：確定
//                        Button {
//                            Task { await confirmGuideSync() }
//                        } label: {
//                            HStack(spacing: 8) {
//                                Image(systemName: "checkmark.circle.fill")
//                                Text("確定")
//                                    .fontWeight(.semibold)
//                            }
//                            .font(.system(size: 16))
//                            .foregroundColor(.white)
//                            .padding(.horizontal, 16)
//                            .padding(.vertical, 10)
//                            .background(Color.blue)
//                            .clipShape(Capsule())
//                            .shadow(radius: 6, y: 2)
//                        }
//                        .padding(.trailing, 20)
//                    }
//                    .padding(.bottom, 100)
//                }
//                .ignoresSafeArea()
//            }
//
//            // 送信完了トースト
//            if showSentToast {
//                VStack {
//                    Spacer()
//                    Text("撮影者にガイドを送信しました")
//                        .font(.callout)
//                        .padding(.horizontal, 16)
//                        .padding(.vertical, 10)
//                        .background(.ultraThinMaterial)
//                        .clipShape(Capsule())
//                        .padding(.bottom, 40)
//                }
//                .transition(.opacity)
//            }
//
//            if let errorMessage {
//                VStack { Spacer(); Text(errorMessage).foregroundColor(.red).padding() }
//            }
//        }
//        // 左上オーバーレイ：room名＋撮影者側のみ受信ログ表示
//        .overlay(alignment: .topLeading) {
//            if role == .photographer {
//                VStack(alignment: .leading, spacing: 6) {
//                    Text("room: \(room.name ?? "-")")
//                        .font(.caption)
//                        .padding(6)
//                        .background(Color.black.opacity(0.4))
//                        .foregroundColor(.white)
//                        .cornerRadius(6)
//
//                    if lastRxLog != "-" {
//                        Text(lastRxLog)
//                            .font(.caption2)
//                            .padding(6)
//                            .background(Color.black.opacity(0.35))
//                            .foregroundColor(.white)
//                            .cornerRadius(6)
//                    }
//                }
//                .padding(EdgeInsets(top: 56, leading: 16, bottom: 16, trailing: 16))
//            } else {
//                Text("room: \(room.name ?? "-")")
//                    .font(.caption)
//                    .padding(6)
//                    .background(Color.black.opacity(0.4))
//                    .foregroundColor(.white)
//                    .cornerRadius(6)
//                    .padding(EdgeInsets(top: 56, leading: 16, bottom: 16, trailing: 16))
//            }
//        }
//        // 透過度スライダ（両役とも上固定）
//        .safeAreaInset(edge: .top) {
//            HStack {
//                Image(systemName: "square.on.square.dashed")
//                Slider(value: Binding(get: {
//                    guideOpacity
//                }, set: { v in
//                    guideOpacity = v
//                }), in: 0.0...1.0)
//                .frame(maxWidth: 260)
//                Text(String(format: "%.0f%%", guideOpacity * 100))
//                    .monospacedDigit()
//            }
//            .padding(.horizontal, 16)
//            .padding(.vertical, 10)
//            .background(.ultraThinMaterial)
//            .clipShape(Capsule())
//            .padding(.top, 6)
//        }
//        // 被写体のサムネトレイ（必要時のみ）
//        .safeAreaInset(edge: .bottom) {
//            if role == .subject && showGuidePicker {
//                HStack(spacing: 10) {
//                    ForEach(0..<photoAssets.count, id: \.self) { idx in
//                        Button {
//                            Task {
//                                await selectGuide(index: idx) // 送信はしない、ローカルのみ
//                                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
//                                    showGuidePicker = false
//                                }
//                            }
//                        } label: {
//                            let img = UIImage(named: photoAssets[idx])
//                            ZStack {
//                                if let ii = img {
//                                    Image(uiImage: ii)
//                                        .resizable()
//                                        .scaledToFill()
//                                        .frame(width: 64, height: 64)
//                                        .clipped()
//                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 1))
//                                } else {
//                                    Color.black.opacity(0.2)
//                                        .frame(width: 64, height: 64)
//                                        .overlay(Text("\(idx+1)").foregroundColor(.white))
//                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 1))
//                                }
//                            }
//                        }
//                        .buttonStyle(.plain)
//                        .overlay(
//                            RoundedRectangle(cornerRadius: 8)
//                                .stroke(idx == selectedGuideIndex ? Color.blue : Color.clear, lineWidth: 3)
//                        )
//                    }
//                }
//                .padding(10)
//                .background(.ultraThinMaterial)
//                .clipShape(RoundedRectangle(cornerRadius: 12))
//                .padding(.bottom, 64)
//                .transition(.move(edge: .bottom).combined(with: .opacity))
//            }
//        }
//        .task {
//            await connectToRoom(
//                roomName: roomName,
//                identity: (role == .photographer ? "photographer" : "subject")
//            )
//        }
//        .onDisappear {
//            Task { await room.disconnect() }
//        }
//    }
//
//    // ===== 被写体の変形ジェスチャ（確定まで送信しない） =====
//    private func subjectTransformGestures() -> some Gesture {
//        let pinch = MagnificationGesture()
//            .onChanged { value in
//                workScale = value
//            }
//            .onEnded { value in
//                baseTransform.scale *= value
//                workScale = 1.0
//            }
//
//        let drag = DragGesture()
//            .onChanged { value in
//                workOffset = value.translation
//            }
//            .onEnded { value in
//                baseTransform.offsetX += value.translation.width
//                baseTransform.offsetY += value.translation.height
//                workOffset = .zero
//            }
//
//        let rotate = RotationGesture()
//            .onChanged { angle in
//                workRotation = angle
//            }
//            .onEnded { angle in
//                baseTransform.rotation += CGFloat(angle.radians)
//                workRotation = .zero
//            }
//
//        return SimultaneousGesture(SimultaneousGesture(pinch, drag), rotate)
//    }
//
//    // ===== デリゲート =====
//    final class MinimalRoomDelegate: NSObject, RoomDelegate {
//        private let onVideo: (VideoTrack) -> Void
//        private let onData: (Data, RemoteParticipant?, String) -> Void
//
//        init(onVideo: @escaping (VideoTrack) -> Void,
//             onData: @escaping (Data, RemoteParticipant?, String) -> Void) {
//            self.onVideo = onVideo
//            self.onData = onData
//        }
//
//        func room(_ room: Room,
//                  participant: RemoteParticipant,
//                  didSubscribeTrack publication: RemoteTrackPublication,
//                  track: Track) {
//            if let v = track as? VideoTrack { onVideo(v) }
//        }
//
//        // LiveKit 1.9 系の最新シグネチャ
//        func room(_ room: Room,
//                  participant: RemoteParticipant?,
//                  didReceiveData data: Data,
//                  forTopic topic: String,
//                  encryptionType: EncryptionType) {
//            onData(data, participant, topic)
//        }
//    }
//
//    // ===== カメラ有無チェック =====
//    private func hasCameraDevice() -> Bool {
//        let session = AVCaptureDevice.DiscoverySession(
//            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
//            mediaType: .video,
//            position: .unspecified
//        )
//        return !session.devices.isEmpty
//    }
//
//    // ===== 接続 =====
//    @MainActor
//    private func connectToRoom(roomName: String, identity: String) async {
//        // 実機から到達可能なIPv4に合わせて変更すること
//        let tokenURL = "http://192.168.50.92:3000/token?roomName=\(roomName)&identity=\(identity)"
//        guard let url = URL(string: tokenURL) else {
//            print("[CONNECT][ERR] token URL invalid:", tokenURL)
//            return
//        }
//
//        do {
//            print("[TOKEN] GET \(tokenURL)")
//            let (data, _) = try await URLSession.shared.data(from: url)
//            let result = try JSONDecoder().decode([String: String].self, from: data)
//            guard let token = result["token"] else { throw URLError(.badServerResponse) }
//            print("[CONNECT] token fetched (len=\(token.count)) for room=\(roomName) identity=\(identity)")
//
//            room.removeAllDelegates()
//            let newDelegate = MinimalRoomDelegate(
//                onVideo: { v in
//                    self.remoteTrack = v
//                    print("[DELEGATE] subscribed remote video")
//                },
//                onData: { data, _, topic in
//                    print("[DATA] received topic:", topic, "bytes:", data.count)
//                    self.handleData(data, topic: topic)
//                }
//            )
//            self.roomDelegate = newDelegate // 強参照保持
//            room.add(delegate: newDelegate)
//
//            let connectOptions = ConnectOptions(autoSubscribe: true)
//            try await room.connect(
//                url: "wss://poseguideapp-u7p300v5.livekit.cloud",
//                token: token,
//                connectOptions: connectOptions
//            )
//            isConnected = true
//            print("[CONNECT] connected to room:", room.name ?? "(nil)")
//
//            if identity == "photographer" {
//                #if targetEnvironment(simulator)
//                self.errorMessage = "カメラの映像がありません（シミュレータではカメラは使えません）"
//                return
//                #else
//                guard hasCameraDevice() else {
//                    self.errorMessage = "カメラの映像がありません（カメラが見つかりません）"
//                    return
//                }
//                try await publishCamera(position: camPos)
//                #endif
//            } else {
//                attachExistingRemoteIfAny()
//                // 被写体は確定まで送らない仕様
//            }
//
//        } catch {
//            print("[CONNECT][ERR] \(error)")
//            self.errorMessage = "接続に失敗しました"
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
//    // ===== データ受信処理（撮影者側で反映＋ログ） =====
//    @MainActor
//    private func handleData(_ data: Data, topic: String) {
//        print("[DATA] received topic:", topic, "bytes:", data.count)
//
//        // ガイド用トピック以外は無視
//        guard topic == guideTopic else { return }
//
//        do {
//            let payload = try JSONDecoder().decode(GuidePayload.self, from: data)
//
//            applyGuide(index: payload.index, transform: payload.transform)
//
//            print("[GUIDE] 変更が届きました index:", payload.index,
//                  "scale:", payload.transform.scale,
//                  "offsetX:", payload.transform.offsetX,
//                  "offsetY:", payload.transform.offsetY,
//                  "rotation(rad):", payload.transform.rotation)
//
//            if role == .photographer {
//                lastRxLog = "変更が届きました  idx:\(payload.index)  s:\(String(format: "%.2f", payload.transform.scale))  x:\(Int(payload.transform.offsetX))  y:\(Int(payload.transform.offsetY))  r:\(String(format: "%.2f", payload.transform.rotation))"
//            }
//
//        } catch {
//            print("[GUIDE][ERR] decode failed:", error.localizedDescription)
//            if role == .photographer {
//                lastRxLog = "受信したがデコード失敗"
//            }
//        }
//    }
//
//    @MainActor
//    private func applyGuide(index: Int, transform: GuideTransform? = nil) {
//        guard frameAssets.indices.contains(index) else { return }
//        selectedGuideIndex = index
//        guideImage = UIImage(named: frameAssets[index])
//        if let t = transform {
//            baseTransform = t
//            workScale = 1.0
//            workOffset = .zero
//            workRotation = .zero
//        }
//    }
//
//    // ===== ガイド選択（ローカルのみ反映・送信なし） =====
//    @MainActor
//    private func selectGuide(index: Int) async {
//        guard frameAssets.indices.contains(index), photoAssets.indices.contains(index) else { return }
//        selectedGuideIndex = index
//        guideImage = UIImage(named: frameAssets[index])
//    }
//
//    // ===== 確定押下で一度だけ送信 =====
//    @MainActor
//    private func confirmGuideSync() async {
//        guard room.connectionState == .connected else { return }
//        let payload = GuidePayload(index: selectedGuideIndex, transform: currentEffectiveTransform)
//        guard let data = try? JSONEncoder().encode(payload) else { return }
//
//        do {
//            // Bool 版の DataPublishOptions
//            let opts = DataPublishOptions(topic: guideTopic, reliable: true)
//            try await room.localParticipant.publish(data: data, options: opts)
//
//            withAnimation(.easeInOut(duration: 0.2)) { showSentToast = true }
//            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
//                withAnimation(.easeInOut(duration: 0.2)) { showSentToast = false }
//            }
//            baseTransform = currentEffectiveTransform
//            workScale = 1.0
//            workOffset = .zero
//            workRotation = .zero
//            print("[GUIDE] sent index:", selectedGuideIndex)
//        } catch {
//            print("[GUIDE][ERR] publish failed:", error.localizedDescription)
//        }
//    }
//
//    // ===== カメラ =====
//    @MainActor
//    private func publishCamera(position: CamPos) async throws {
//        if let track = localTrack,
//           let capturer = track.capturer as? CameraCapturer {
//            do {
//                try await capturer.set(cameraPosition: position == .front ? .front : .back)
//                camPos = position
//                print("[CAMERA] switched (reuse track): \(position == .front ? "front" : "back")")
//                return
//            } catch {
//                let ns = error as NSError
//                if ns.domain == "io.livekit.swift-sdk", ns.code == 701 {
//                    self.errorMessage = "カメラの映像がありません（デバイスが見つかりません）"
//                    return
//                }
//                throw error
//            }
//        }
//
//        let options = CameraCaptureOptions(position: position == .front ? .front : .back)
//        let cam = LocalVideoTrack.createCameraTrack(options: options)
//        self.localTrack = cam
//        do {
//            let pub: LocalTrackPublication = try await room.localParticipant.publish(videoTrack: cam)
//            self.localPub = pub
//            camPos = position
//            print("[CAMERA] published video (\(position == .front ? "front" : "back"))")
//        } catch {
//            let ns = error as NSError
//            if ns.domain == "io.livekit.swift-sdk", ns.code == 701 {
//                self.errorMessage = "カメラの映像がありません（デバイスが見つかりません）"
//                return
//            }
//            throw error
//        }
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
//            self.errorMessage = self.errorMessage ?? "カメラ切替に失敗しました"
//        }
//    }
//
//    // ===== 撮影（ガイド無しの生写真を保存） =====
//    @MainActor
//    private func captureWithAVFoundation() async {
//        guard role == .photographer else { return }
//
//        if PHPhotoLibrary.authorizationStatus(for: .addOnly) == .notDetermined {
//            _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
//        }
//        guard PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized else {
//            self.errorMessage = "写真への保存が許可されていません（設定で許可してください）"
//            return
//        }
//
//        // 1) LiveKit 側カメラを一時停止
//        let resumePos: CamPos = camPos
//        if let track = localTrack, let capturer = track.capturer as? CameraCapturer {
//            do {
//                try await capturer.stopCapture()
//                try? await Task.sleep(nanoseconds: 150_000_000)
//            } catch {
//                print("[SHOT] stopCapture error: \(error)")
//            }
//        }
//
//        // 2) AVFoundation で生写真を1枚撮影
//        let prefer: AVCaptureDevice.Position = (resumePos == .front) ? .front : .back
//
//        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
//            singleShot.capture(prefer: prefer) { image in
//                if let img = image {
//                    PHPhotoLibrary.shared().performChanges({
//                        PHAssetChangeRequest.creationRequestForAsset(from: img)
//                    }) { success, err in
//                        DispatchQueue.main.async {
//                            if success { print("[SHOT] saved to library") }
//                            else {
//                                self.errorMessage = "保存に失敗しました"
//                                print("[SHOT][ERR] \(err?.localizedDescription ?? "unknown")")
//                            }
//                            cont.resume()
//                        }
//                    }
//                } else {
//                    DispatchQueue.main.async {
//                        self.errorMessage = "撮影に失敗しました"
//                        cont.resume()
//                    }
//                }
//            }
//        }
//
//        // 3) LiveKit のカメラを再開
//        if let track = localTrack, let capturer = track.capturer as? CameraCapturer {
//            do {
//                try await capturer.startCapture()
//                try await capturer.set(cameraPosition: (resumePos == .front ? .front : .back))
//                print("[SHOT] camera restarted (\(resumePos == .front ? "front" : "back"))")
//            } catch {
//                print("[SHOT][ERR] restart failed: \(error)")
//            }
//        }
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

// ===== ガイド無しで 1 枚だけ写真を撮って UIImage を返す (セッション再利用) =====
final class SingleShotCapturer: NSObject, AVCapturePhotoCaptureDelegate {
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "single-shot")
    private var completion: ((UIImage?) -> Void)?

    func capture(prefer position: AVCaptureDevice.Position,
                 completion: @escaping (UIImage?) -> Void) {
        self.completion = completion

        session.beginConfiguration()
        session.sessionPreset = .photo

        // すでに追加されている入力・出力をクリアしてから再設定
        for input in session.inputs {
            session.removeInput(input)
        }
        for out in session.outputs {
            session.removeOutput(out)
        }

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
            session.commitConfiguration()
            completion(nil)
            return
        }
        session.addOutput(output)
        output.isHighResolutionCaptureEnabled = true

        session.commitConfiguration()

        queue.async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
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
            completion?(nil)
            completion = nil
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            completion?(nil)
            completion = nil
            return
        }
        completion?(image)
        completion = nil
    }
}

// ===== 同期用モデル =====
struct GuideTransform: Codable, Equatable {
    var scale: CGFloat = 1.0
    var offsetX: CGFloat = 0.0
    var offsetY: CGFloat = 0.0
    var rotation: CGFloat = 0.0 // ラジアン
}

struct GuidePayload: Codable, Equatable {
    var index: Int
    var transform: GuideTransform
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
    @State private var roomDelegate: MinimalRoomDelegate? // 強参照保持が必須

    // 映像
    @State private var remoteTrack: VideoTrack?
    @State private var localTrack: LocalVideoTrack?
    @State private var localPub: LocalTrackPublication?

    // カメラ向き
    enum CamPos { case front, back }
    @State private var camPos: CamPos = .front

    // データチャンネル
    private let guideTopic = "guide-sync"

    // 被写体が選ぶサムネ（写真）: お手本
    private let photoAssets = [
        "pose_guide1",
        "pose_guide2",
        "pose_guide3",
        "pose_guide4"
    ]

    // 実際に重ねるフレーム（シルエット）
    private let frameAssets = [
        "pose_guide1_silhouette",
        "pose_guide2_silhouette",
        "pose_guide3_silhouette",
        "pose_guide4_silhouette"
    ]

    @State private var selectedGuideIndex: Int = 0
    @State private var guideImage: UIImage? = UIImage(named: "pose_guide1_silhouette")

    // 透過度（両者共通UI・上固定）
    @State private var guideOpacity: CGFloat = 1.0

    // ガイド変形（確定前の作業用と確定後の本体を分離）
    @State private var baseTransform = GuideTransform()       // 確定済みの基準
    @State private var workScale: CGFloat = 1.0               // ジェスチャ中の一時値
    @State private var workOffset: CGSize = .zero
    @State private var workRotation: Angle = .zero

    // 被写体 UI
    @State private var showGuidePicker = false
    @State private var showSentToast = false

    // 受信ログの簡易表示（撮影者側だけ）
    @State private var lastRxLog: String = "-"

    // 生写真キャプチャ
    private let singleShot = SingleShotCapturer()

    // 現在の見た目に効く合成変形
    private var effScale: CGFloat { baseTransform.scale * workScale }
    private var effRotation: Angle { Angle(radians: Double(baseTransform.rotation)) + workRotation }
    private var effOffset: CGSize {
        CGSize(width: baseTransform.offsetX + workOffset.width,
               height: baseTransform.offsetY + workOffset.height)
    }

    // 現在の確定すべき状態
    private var currentEffectiveTransform: GuideTransform {
        var t = baseTransform
        t.scale *= workScale
        t.offsetX += workOffset.width
        t.offsetY += workOffset.height
        t.rotation += CGFloat(workRotation.radians)
        return t
    }

    // 現在選択中のガイドに対応するお手本写真 (右上プレビュー用)
    private var referenceImage: UIImage? {
        guard photoAssets.indices.contains(selectedGuideIndex) else { return nil }
        return UIImage(named: photoAssets[selectedGuideIndex])
    }

    // ===== body =====
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            previewArea
            photographerUI
            subjectUI
            toastAndError
        }
        .overlay(roomInfoOverlay, alignment: .topLeading)
        .overlay(referenceOverlay, alignment: .topTrailing)
        .safeAreaInset(edge: .top) { opacitySlider }
        .safeAreaInset(edge: .bottom) { guideTray }
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

    // ===== 4:3 プレビュー部分 =====
    @ViewBuilder
    private var previewArea: some View {
        GeometryReader { geo in
            let screenSize = geo.size
            let containerSize = containerSizeFor4to3(screenSize: screenSize)

            ZStack {
                // 映像レイヤ
                if isConnected {
                    if role == .photographer, let lt = localTrack {
                        VideoHostView(track: lt, contentMode: .scaleAspectFit)
                            .clipped()
                    } else if role == .subject, let rt = remoteTrack {
                        VideoHostView(track: rt, contentMode: .scaleAspectFit)
                            .clipped()
                    } else {
                        Color.black
                            .overlay(
                                Text("映像を待っています")
                                    .foregroundColor(.white)
                            )
                    }
                } else {
                    Color.gray.opacity(0.3)
                        .overlay(
                            Text("接続中...")
                                .foregroundColor(.black)
                        )
                }

                // ガイド
                if let g = guideImage {
                    Image(uiImage: g)
                        .resizable()
                        .scaledToFit()
                        .opacity(guideOpacity)
                        .scaleEffect(effScale)
                        .rotationEffect(effRotation)
                        .offset(effOffset)
                        .allowsHitTesting(role == .subject)
                        .gesture(role == .subject ? subjectTransformGestures() : nil)
                }
            }
            .frame(width: containerSize.width, height: containerSize.height)
            .position(x: screenSize.width / 2, y: screenSize.height / 2)
        }
    }

    private func containerSizeFor4to3(screenSize: CGSize) -> CGSize {
        // targetRatio = width / height = 3:4
        let targetRatio: CGFloat = 3.0 / 4.0
        let screenRatio = screenSize.width / screenSize.height

        if screenRatio > targetRatio {
            // 画面の方が横長 => 高さ基準
            let h = screenSize.height
            let w = h * targetRatio
            return CGSize(width: w, height: h)
        } else {
            // 画面の方が縦長 or ちょうど => 幅基準
            let w = screenSize.width
            let h = w / targetRatio
            return CGSize(width: w, height: h)
        }
    }

    // ===== 撮影者 UI =====
    @ViewBuilder
    private var photographerUI: some View {
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
                    .padding(.bottom, 120)
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
    }

    // ===== 被写体 UI =====
    @ViewBuilder
    private var subjectUI: some View {
        if role == .subject {
            VStack {
                Spacer()
                HStack {
                    // 左下：トグル
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            showGuidePicker.toggle()
                        }
                    } label: {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(width: 48, height: 48)
                            .background(.white)
                            .clipShape(Circle())
                            .shadow(radius: 6, y: 2)
                            .overlay(
                                Group {
                                    if showGuidePicker {
                                        Circle().stroke(Color.blue, lineWidth: 2)
                                    }
                                }
                            )
                    }
                    .padding(.leading, 20)

                    Spacer()

                    // 右下：確定
                    Button {
                        Task { await confirmGuideSync() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("確定")
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .clipShape(Capsule())
                        .shadow(radius: 6, y: 2)
                    }
                    .padding(.trailing, 20)
                }
                .padding(.bottom, 100)
            }
            .ignoresSafeArea()
        }
    }

    // ===== トーストとエラー =====
    @ViewBuilder
    private var toastAndError: some View {
        if showSentToast {
            VStack {
                Spacer()
                Text("撮影者にガイドを送信しました")
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 40)
            }
            .transition(.opacity)
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

    // ===== 左上 room 情報オーバーレイ =====
    @ViewBuilder
    private var roomInfoOverlay: some View {
        if role == .photographer {
            VStack(alignment: .leading, spacing: 6) {
                Text("room: \(room.name ?? "-")")
                    .font(.caption)
                    .padding(6)
                    .background(Color.black.opacity(0.4))
                    .foregroundColor(.white)
                    .cornerRadius(6)

                if lastRxLog != "-" {
                    Text(lastRxLog)
                        .font(.caption2)
                        .padding(6)
                        .background(Color.black.opacity(0.35))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
            }
            .padding(EdgeInsets(top: 56, leading: 16, bottom: 16, trailing: 16))
        } else {
            Text("room: \(room.name ?? "-")")
                .font(.caption)
                .padding(6)
                .background(Color.black.opacity(0.4))
                .foregroundColor(.white)
                .cornerRadius(6)
                .padding(EdgeInsets(top: 56, leading: 16, bottom: 16, trailing: 16))
        }
    }

    // ===== 右上 お手本プレビュー =====
    @ViewBuilder
    private var referenceOverlay: some View {
        if let ref = referenceImage {
            VStack(alignment: .trailing, spacing: 4) {
                Text("お手本")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())

                Image(uiImage: ref)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.8), lineWidth: 1)
                    )
                    .shadow(radius: 4, y: 2)
            }
            .padding(EdgeInsets(top: 64, leading: 16, bottom: 16, trailing: 16))
        }
    }

    // ===== 上部 透過度スライダ =====
    private var opacitySlider: some View {
        HStack {
            Image(systemName: "square.on.square.dashed")
            Slider(value: Binding(get: {
                guideOpacity
            }, set: { v in
                guideOpacity = v
            }), in: 0.0...1.0)
            .frame(maxWidth: 260)
            Text(String(format: "%.0f%%", guideOpacity * 100))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.top, 6)
    }

    // ===== 下部 サムネトレイ =====
    @ViewBuilder
    private var guideTray: some View {
        if role == .subject && showGuidePicker {
            HStack(spacing: 10) {
                ForEach(0..<photoAssets.count, id: \.self) { idx in
                    Button {
                        Task {
                            await selectGuide(index: idx) // 送信はしない、ローカルのみ
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                showGuidePicker = false
                            }
                        }
                    } label: {
                        let img = UIImage(named: photoAssets[idx])
                        ZStack {
                            if let ii = img {
                                Image(uiImage: ii)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipped()
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white, lineWidth: 1)
                                    )
                            } else {
                                Color.black.opacity(0.2)
                                    .frame(width: 64, height: 64)
                                    .overlay(Text("\(idx+1)").foregroundColor(.white))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white, lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(idx == selectedGuideIndex ? Color.blue : Color.clear, lineWidth: 3)
                    )
                }
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 64)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // ===== 被写体の変形ジェスチャ（確定まで送信しない） =====
    private func subjectTransformGestures() -> some Gesture {
        let pinch = MagnificationGesture()
            .onChanged { value in
                workScale = value
            }
            .onEnded { value in
                baseTransform.scale *= value
                workScale = 1.0
            }

        let drag = DragGesture()
            .onChanged { value in
                workOffset = value.translation
            }
            .onEnded { value in
                baseTransform.offsetX += value.translation.width
                baseTransform.offsetY += value.translation.height
                workOffset = .zero
            }

        let rotate = RotationGesture()
            .onChanged { angle in
                workRotation = angle
            }
            .onEnded { angle in
                baseTransform.rotation += CGFloat(angle.radians)
                workRotation = .zero
            }

        return SimultaneousGesture(SimultaneousGesture(pinch, drag), rotate)
    }

    // ===== デリゲート =====
    final class MinimalRoomDelegate: NSObject, RoomDelegate {
        private let onVideo: (VideoTrack) -> Void
        private let onData: (Data, RemoteParticipant?, String) -> Void

        init(onVideo: @escaping (VideoTrack) -> Void,
             onData: @escaping (Data, RemoteParticipant?, String) -> Void) {
            self.onVideo = onVideo
            self.onData = onData
        }

        func room(_ room: Room,
                  participant: RemoteParticipant,
                  didSubscribeTrack publication: RemoteTrackPublication,
                  track: Track) {
            if let v = track as? VideoTrack { onVideo(v) }
        }

        // LiveKit 1.9 系の最新シグネチャ
        func room(_ room: Room,
                  participant: RemoteParticipant?,
                  didReceiveData data: Data,
                  forTopic topic: String,
                  encryptionType: EncryptionType) {
            onData(data, participant, topic)
        }
    }

    // ===== カメラ有無チェック =====
    private func hasCameraDevice() -> Bool {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .unspecified
        )
        return !session.devices.isEmpty
    }

    // ===== 接続 =====
    @MainActor
    private func connectToRoom(roomName: String, identity: String) async {
        // 実機から到達可能なIPv4に合わせて変更すること
        let tokenURL = "http://192.168.50.92:3000/token?roomName=\(roomName)&identity=\(identity)"
        guard let url = URL(string: tokenURL) else {
            print("[CONNECT][ERR] token URL invalid:", tokenURL)
            return
        }

        do {
            print("[TOKEN] GET \(tokenURL)")
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try JSONDecoder().decode([String: String].self, from: data)
            guard let token = result["token"] else { throw URLError(.badServerResponse) }
            print("[CONNECT] token fetched (len=\(token.count)) for room=\(roomName) identity=\(identity)")

            room.removeAllDelegates()
            let newDelegate = MinimalRoomDelegate(
                onVideo: { v in
                    self.remoteTrack = v
                    print("[DELEGATE] subscribed remote video")
                },
                onData: { data, _, topic in
                    print("[DATA] received topic:", topic, "bytes:", data.count)
                    self.handleData(data, topic: topic)
                }
            )
            self.roomDelegate = newDelegate // 強参照保持
            room.add(delegate: newDelegate)

            let connectOptions = ConnectOptions(autoSubscribe: true)
            try await room.connect(
                url: "wss://poseguideapp-u7p300v5.livekit.cloud",
                token: token,
                connectOptions: connectOptions
            )
            isConnected = true
            print("[CONNECT] connected to room:", room.name ?? "(nil)")

            if identity == "photographer" {
                #if targetEnvironment(simulator)
                self.errorMessage = "カメラの映像がありません（シミュレータではカメラは使えません）"
                return
                #else
                guard hasCameraDevice() else {
                    self.errorMessage = "カメラの映像がありません（カメラが見つかりません）"
                    return
                }
                try await publishCamera(position: camPos)
                #endif
            } else {
                attachExistingRemoteIfAny()
                // 被写体は確定まで送らない仕様
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

    // ===== データ受信処理（撮影者側で反映＋ログ） =====
    @MainActor
    private func handleData(_ data: Data, topic: String) {
        print("[DATA] received topic:", topic, "bytes:", data.count)

        // ガイド用トピック以外は無視
        guard topic == guideTopic else { return }

        do {
            let payload = try JSONDecoder().decode(GuidePayload.self, from: data)

            applyGuide(index: payload.index, transform: payload.transform)

            print("[GUIDE] 変更が届きました index:", payload.index,
                  "scale:", payload.transform.scale,
                  "offsetX:", payload.transform.offsetX,
                  "offsetY:", payload.transform.offsetY,
                  "rotation(rad):", payload.transform.rotation)

            if role == .photographer {
                lastRxLog = "変更が届きました  idx:\(payload.index)  s:\(String(format: "%.2f", payload.transform.scale))  x:\(Int(payload.transform.offsetX))  y:\(Int(payload.transform.offsetY))  r:\(String(format: "%.2f", payload.transform.rotation))"
            }

        } catch {
            print("[GUIDE][ERR] decode failed:", error.localizedDescription)
            if role == .photographer {
                lastRxLog = "受信したがデコード失敗"
            }
        }
    }

    @MainActor
    private func applyGuide(index: Int, transform: GuideTransform? = nil) {
        guard frameAssets.indices.contains(index) else { return }
        selectedGuideIndex = index
        guideImage = UIImage(named: frameAssets[index])
        if let t = transform {
            baseTransform = t
            workScale = 1.0
            workOffset = .zero
            workRotation = .zero
        }
    }

    // ===== ガイド選択（ローカルのみ反映・送信なし） =====
    @MainActor
    private func selectGuide(index: Int) async {
        guard frameAssets.indices.contains(index), photoAssets.indices.contains(index) else { return }
        selectedGuideIndex = index
        guideImage = UIImage(named: frameAssets[index])
    }

    // ===== 確定押下で一度だけ送信 =====
    @MainActor
    private func confirmGuideSync() async {
        guard room.connectionState == .connected else { return }
        let payload = GuidePayload(index: selectedGuideIndex, transform: currentEffectiveTransform)
        guard let data = try? JSONEncoder().encode(payload) else { return }

        do {
            let opts = DataPublishOptions(topic: guideTopic, reliable: true)
            try await room.localParticipant.publish(data: data, options: opts)

            withAnimation(.easeInOut(duration: 0.2)) { showSentToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeInOut(duration: 0.2)) { showSentToast = false }
            }
            baseTransform = currentEffectiveTransform
            workScale = 1.0
            workOffset = .zero
            workRotation = .zero
            print("[GUIDE] sent index:", selectedGuideIndex)
        } catch {
            print("[GUIDE][ERR] publish failed:", error.localizedDescription)
        }
    }

    // ===== カメラ =====
    @MainActor
    private func publishCamera(position: CamPos) async throws {
        if let track = localTrack,
           let capturer = track.capturer as? CameraCapturer {
            do {
                try await capturer.set(cameraPosition: position == .front ? .front : .back)
                camPos = position
                print("[CAMERA] switched (reuse track): \(position == .front ? "front" : "back")")
                return
            } catch {
                let ns = error as NSError
                if ns.domain == "io.livekit.swift-sdk", ns.code == 701 {
                    self.errorMessage = "カメラの映像がありません（デバイスが見つかりません）"
                    return
                }
                throw error
            }
        }

        let options = CameraCaptureOptions(position: position == .front ? .front : .back)
        let cam = LocalVideoTrack.createCameraTrack(options: options)
        self.localTrack = cam
        do {
            let pub: LocalTrackPublication = try await room.localParticipant.publish(videoTrack: cam)
            self.localPub = pub
            camPos = position
            print("[CAMERA] published video (\(position == .front ? "front" : "back"))")
        } catch {
            let ns = error as NSError
            if ns.domain == "io.livekit.swift-sdk", ns.code == 701 {
                self.errorMessage = "カメラの映像がありません（デバイスが見つかりません）"
                return
            }
            throw error
        }
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
            self.errorMessage = self.errorMessage ?? "カメラ切替に失敗しました"
        }
    }

    // ===== 撮影（ガイド無しの生写真を保存） =====
    @MainActor
    private func captureWithAVFoundation() async {
        guard role == .photographer else { return }

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
