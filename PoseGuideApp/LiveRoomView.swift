import SwiftUI

struct LiveRoomView: View {
    let role: UserRole
    @State private var sampleImage: UIImage? = UIImage(named: "sample_pose") // デモ用
    @State private var showImagePicker = false

    var body: some View {
        ZStack {
            // 背景：それぞれのカメラ映像想定
            if role == .photographer {
                Color.blue.opacity(0.2)
                    .overlay(Text("📷 撮影者カメラ映像（自分）").foregroundColor(.white))
            } else {
                Color.purple.opacity(0.2)
                    .overlay(Text("🤳 被写体ビュー（相手カメラ）").foregroundColor(.white))
            }

            // お手本写真（共通表示）
            if let image = sampleImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .opacity(0.5)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            //オーバーレイ部分
            if role == .photographer {
                PhotographerOverlay()
            } else {
                SubjectOverlay()
            }

            // 下部の操作ボタンやテキスト
            VStack {
                Spacer()
                if role == .subject {
                    Button("📸 お手本写真を選択") {
                        showImagePicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 40)
                } else {
                    Text("被写体がアップロードしたお手本を表示中")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $sampleImage)
        }
    }
}

