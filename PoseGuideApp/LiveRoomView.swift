import SwiftUI

struct LiveRoomView: View {
    let role: UserRole
    
    // 📸 お手本 or フレーム画像
    @State private var guideFrame: UIImage? = UIImage(named: "pose_guide1_silhouette") // Assetsに入れておく
    
    // ✨ フレーム調整用パラメータ
    @State private var opacity: Double = 0.7
    @State private var scale: CGFloat = 1.0
    @State private var offsetX: CGFloat = 0
    @State private var offsetY: CGFloat = 0
    
    // 🎨 フレーム画像を後で変更できるように
    @State private var showImagePicker = false
    @State private var sampleImage: UIImage? = UIImage(named: "sample_pose")

    var body: some View {
        ZStack {
            // 背景（カメラ映像想定）
            if role == .photographer {
                Color.blue.opacity(0.2)
                    .overlay(Text("📷 撮影者ビュー").foregroundColor(.white))
                    .ignoresSafeArea()
            } else {
                Color.purple.opacity(0.2)
                    .overlay(Text("🤳 被写体ビュー").foregroundColor(.white))
                    .ignoresSafeArea()
            }
            
            // お手本写真（被写体がアップロードする想定）
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

            // ✅ フレーム画像を重ねる
            if let frame = guideFrame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .offset(x: offsetX, y: offsetY)
                    .animation(.easeInOut(duration: 0.2), value: [scale, offsetX, offsetY, opacity])
                    .allowsHitTesting(false)
            }

            // ✅ スライダーUI
            VStack {
                Spacer()
                VStack(spacing: 12) {
                    Text("フレーム調整")
                        .font(.headline)
                        .foregroundColor(.white)

                    // 透明度
                    HStack {
                        Text("透明度").foregroundColor(.white)
                        Slider(value: $opacity, in: 0...1)
                    }

                    // 拡大縮小
                    HStack {
                        Text("サイズ").foregroundColor(.white)
                        Slider(value: $scale, in: 0.5...2)
                    }

                    // 左右位置
                    HStack {
                        Text("左右").foregroundColor(.white)
                        Slider(value: $offsetX, in: -150...150)
                    }

                    // 上下位置
                    HStack {
                        Text("上下").foregroundColor(.white)
                        Slider(value: $offsetY, in: -200...200)
                    }

                    // 被写体だけが「お手本写真を選択」できる
                    if role == .subject {
                        Button("📸 お手本写真を選択") {
                            showImagePicker = true
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 10)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.5))
                .cornerRadius(16)
                .padding(.bottom, 20)
            }
        }
        // お手本選択シート
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $sampleImage)
        }
    }
}

