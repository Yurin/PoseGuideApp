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
//    // ガイド（不透明度のみ調整）
//    @State private var guideImage: UIImage? = UIImage(named: "pose_guide1_silhouette")
//    @State private var guide = GuideState() // opacity を利用
//
//    // 生写真キャプチャ
//    private let singleShot = SingleShotCapturer()
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
//            // ===== ガイド重畳（両者に表示・不透明度だけ調整可） =====
//            if let g = guideImage {
//                Image(uiImage: g)
//                    .resizable()
//                    .scaledToFit()
//                    .opacity(guide.opacity)
//                    .allowsHitTesting(false)
//                    .animation(.easeInOut(duration: 0.15), value: guide.opacity)
//            }
//
//            // ===== 下部：ガイド不透明度スライダ（両者） =====
//            VStack {
//                Spacer()
//                HStack {
//                    Image(systemName: "square.on.square.dashed")
//                    Slider(value: Binding(get: {
//                        guide.opacity
//                    }, set: { v in
//                        guide.opacity = v
//                    }), in: 0.0...1.0)
//                    .frame(maxWidth: 240)
//                    Text(String(format: "%.0f%%", guide.opacity * 100))
//                        .monospacedDigit()
//                }
//                .padding(.horizontal, 16)
//                .padding(.vertical, 10)
//                .background(.ultraThinMaterial)
//                .clipShape(Capsule())
//                .padding(.bottom, role == .photographer ? 110 : 24)
//            }
//            .ignoresSafeArea()
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
//                        .padding(.bottom, 110)
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
//            if let errorMessage {
//                VStack { Spacer(); Text(errorMessage).foregroundColor(.red).padding() }
//            }
//        }
//        .overlay(alignment: .topLeading) {
//            Text("room: \(room.name ?? "-")")
//                .font(.caption)
//                .padding(6)
//                .background(Color.black.opacity(0.4))
//                .foregroundColor(.white)
//                .cornerRadius(6)
//                .padding()
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
//    // ===== 最小デリゲート（購読時に VideoTrack を拾うだけ） =====
//    final class MinimalRoomDelegate: NSObject, RoomDelegate {
//        private let onVideo: (VideoTrack) -> Void
//        init(onVideo: @escaping (VideoTrack) -> Void) {
//            self.onVideo = onVideo
//        }
//        func room(_ room: Room,
//                  participant: RemoteParticipant,
//                  didSubscribeTrack publication: RemoteTrackPublication,
//                  track: Track) {
//            if let v = track as? VideoTrack { onVideo(v) }
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
//        let tokenURL = "http://172.30.57.208:3000/token?roomName=\(roomName)&identity=\(identity)"
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
//            let delegate = MinimalRoomDelegate { v in
//                self.remoteTrack = v
//                print("[DELEGATE] subscribed remote video")
//            }
//            room.add(delegate: delegate)
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
//                // シミュレータではカメラ不可なので明示的に案内して終了
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
//            // ここは publishCamera 内で 701 を握って errorMessage を出すので、総称の文言だけ残す
//            self.errorMessage = self.errorMessage ?? "カメラ切替に失敗しました"
//        }
//    }
//
//    // ===== 撮影（ガイド無しの生写真を保存） =====
//    @MainActor
//    private func captureWithAVFoundation() async {
//        guard role == .photographer else { return }
//
//        // 追加専用の権限
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
//

// LiveRoomView.swift

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

    // ガイド関連（被写体が選ぶ写真 → 実際に重ねるシルエットの対応）
    private let guideTopic = "guide-selection"

    // 被写体が選ぶサムネ（写真）
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
    @State private var guide = GuideState()

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

            // ===== 被写体 UI：4枚の候補から選択 =====
            if role == .subject {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        ForEach(0..<photoAssets.count, id: \.self) { idx in
                            Button {
                                Task { await selectGuide(index: idx, broadcast: true) }
                            } label: {
                                let img = UIImage(named: photoAssets[idx])
                                ZStack {
                                    if let ii = img {
                                        Image(uiImage: ii)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 64, height: 64)
                                            .clipped()
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 1))
                                    } else {
                                        Color.black.opacity(0.2)
                                            .frame(width: 64, height: 64)
                                            .overlay(Text("\(idx+1)").foregroundColor(.white))
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white, lineWidth: 1))
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

    // ===== デリゲート =====
    final class MinimalRoomDelegate: NSObject, RoomDelegate {
        private let onVideo: (VideoTrack) -> Void
        private let onData: (Data, RemoteParticipant?, String?) -> Void
        private let onParticipantJoined: (RemoteParticipant) -> Void

        init(onVideo: @escaping (VideoTrack) -> Void,
             onData: @escaping (Data, RemoteParticipant?, String?) -> Void,
             onParticipantJoined: @escaping (RemoteParticipant) -> Void) {
            self.onVideo = onVideo
            self.onData = onData
            self.onParticipantJoined = onParticipantJoined
        }

        func room(_ room: Room,
                  participant: RemoteParticipant,
                  didSubscribeTrack publication: RemoteTrackPublication,
                  track: Track) {
            if let v = track as? VideoTrack { onVideo(v) }
        }

        func room(_ room: Room,
                  participant: RemoteParticipant?,
                  didReceive data: Data,
                  topic: String?) {
            onData(data, participant, topic)
        }

        func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
            onParticipantJoined(participant)
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
            let delegate = MinimalRoomDelegate(
                onVideo: { v in
                    self.remoteTrack = v
                    print("[DELEGATE] subscribed remote video")
                },
                onData: { data, _, topic in
                    self.handleData(data, topic: topic)
                },
                onParticipantJoined: { _ in
                    // 被写体は新規参加者に現行選択を再通知
                    if self.role == .subject {
                        Task { await self.broadcastCurrentGuide() }
                    }
                }
            )
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
                // 被写体は入室時に現行選択を一度ブロードキャストして同期
                await broadcastCurrentGuide()
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

    // ===== データ受信処理 =====
    @MainActor
    private func handleData(_ data: Data, topic: String?) {
        guard topic == guideTopic else { return }
        if let text = String(data: data, encoding: .utf8),
           let idx = Int(text), frameAssets.indices.contains(idx) {
            selectedGuideIndex = idx
            guideImage = UIImage(named: frameAssets[idx])
            print("[GUIDE] applied index:", idx)
        }
    }

    // ===== ガイド選択とブロードキャスト =====
    @MainActor
    private func selectGuide(index: Int, broadcast: Bool) async {
        guard frameAssets.indices.contains(index), photoAssets.indices.contains(index) else { return }
        selectedGuideIndex = index
        guideImage = UIImage(named: frameAssets[index])  // 重ねるのは silhouette 側

        if broadcast {
            let payload = Data(String(index).utf8)
            do {
                let opts = DataPublishOptions(topic: guideTopic)
                try await room.localParticipant.publish(data: payload, options: opts)
                print("[GUIDE] broadcast index:", index)
            } catch {
                print("[GUIDE][ERR] publish failed:", error.localizedDescription)
            }
        }
    }

    @MainActor
    private func broadcastCurrentGuide() async {
        await selectGuide(index: selectedGuideIndex, broadcast: true)
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
