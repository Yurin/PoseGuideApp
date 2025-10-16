import SwiftUI

struct LiveRoomView: View {
    let role: UserRole
    let roomName: String   // ← 合言葉（部屋名）を受け取る
    
    // お手本・フレーム画像
    @State private var guideFrame: UIImage? = nil
    @State private var sampleImage: UIImage? = nil
    
    // フレーム調整用パラメータ
    @State private var opacity: Double = 0.7
    @State private var scale: CGFloat = 1.0
    @State private var offsetX: CGFloat = 0
    @State private var offsetY: CGFloat = 0
    @State private var lastDragOffset = CGSize.zero
    @State private var lastScale: CGFloat = 1.0

    // UI状態
    @State private var showImagePicker = false
    @State private var isGenerating = false  // フレーム生成中フラグ

    var body: some View {
        ZStack {
            // 背景（カメラ映像想定）
            if role == .photographer {
                Color.blue.opacity(0.2)
                    .overlay(Text("撮影者ビュー").foregroundColor(.white))
                    .ignoresSafeArea()
            } else {
                Color.purple.opacity(0.2)
                    .overlay(Text("被写体ビュー").foregroundColor(.white))
                    .ignoresSafeArea()
            }

            // 合言葉（ルーム名）を上部に表示
            VStack {
                Text("Room: \(roomName)")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.top, 50)
                    .shadow(radius: 3)
                Spacer()
            }

            // お手本写真（選択後に背面に表示）
            if let sample = sampleImage {
                Image(uiImage: sample)
                    .resizable()
                    .scaledToFit()
                    .opacity(0.5)
                    .padding()
            }

            // 役割別オーバーレイ（構図線など）
            if role == .photographer {
                PhotographerOverlay()
            } else {
                SubjectOverlay()
            }

            // フレーム画像（生成後のみ表示）
            if let frame = guideFrame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .offset(x: offsetX, y: offsetY)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                offsetX = lastDragOffset.width + value.translation.width
                                offsetY = lastDragOffset.height + value.translation.height
                            }
                            .onEnded { _ in
                                lastDragOffset = CGSize(width: offsetX, height: offsetY)
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                    )
                    .animation(.easeInOut(duration: 0.2), value: [scale, offsetX, offsetY, opacity])
            }

            // 状態に応じた下部UI
            VStack {
                Spacer()

                if role == .subject {
                    if sampleImage == nil {
                        // お手本未選択時
                        Button("お手本写真を選択") {
                            showImagePicker = true
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 40)
                    } else if isGenerating {
                        // フレーム生成中
                        ProgressView("フレーム生成中...")
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .foregroundColor(.white)
                            .padding(.bottom, 40)
                    } else if guideFrame != nil {
                        // フレーム生成済み
                        Text("フレームをドラッグやピンチで調整できます")
                            .foregroundColor(.white)
                            .padding(.bottom, 40)
                    }
                }
            }
        }
        // 被写体が画像を選択したらフレーム生成をトリガー
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $sampleImage)
                .onDisappear {
                    if sampleImage != nil {
                        generateFrame()
                    }
                }
        }
    }

    // 仮のフレーム生成（サーバー接続前の疑似処理）
    func generateFrame() {
        isGenerating = true
        guideFrame = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guideFrame = UIImage(named: "pose_guide1_silhouette")
            isGenerating = false
        }
    }
}

