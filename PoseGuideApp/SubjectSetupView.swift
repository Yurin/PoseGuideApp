import SwiftUI
import PhotosUI

struct SubjectSetupView: View {
    let role: LiveRoomView.UserRole
    let roomName: String

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

    // サンプルかカメラロールか
    @State private var useSample = true

    // サンプルの選択 index
    @State private var selectedSampleIndex: Int = 0

    // カメラロール関連
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?

    // LiveRoomView に渡す最終フレーム画像
    @State private var frameImage: UIImage?

    // 遷移用
    @State private var goLive = false

    // 状態表示
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("写真の選択方法") {
                Picker("写真ソース", selection: $useSample) {
                    Text("サンプルから選ぶ").tag(true)
                    Text("カメラロールから選ぶ").tag(false)
                }
                .pickerStyle(.segmented)
            }

            if useSample {
                sampleSection
            } else {
                cameraRollSection
            }

            if let frame = frameImage {
                Section("フレームプレビュー") {
                    Image(uiImage: frame)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                }
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            }

            Section {
                Button {
                    prepareFrameAndGo()
                } label: {
                    if isProcessing {
                        ProgressView()
                    } else {
                        Text("フレームを用意して撮影へ")
                    }
                }
                .disabled(isProcessing || (useSample == false && pickedImage == nil))
            }
        }
        .navigationTitle("被写体の準備")
        .onAppear {
            // 起動時にデフォルトサンプルをセット
            if frameImage == nil {
                selectSample(index: selectedSampleIndex)
            }
        }
        .onChange(of: pickerItem) { newItem in
            Task {
                await loadPickedImage(from: newItem)
            }
        }
        .navigationDestination(isPresented: $goLive) {
            LiveRoomView(
                role: role,
                roomName: roomName,
                initialGuideFrame: frameImage,
                initialGuideIndex: useSample ? selectedSampleIndex : nil
            )
        }
    }

    // MARK: - サンプル一覧表示

    private var sampleSection: some View {
        Section("サンプルから選択") {
            ForEach(photoAssets.indices, id: \.self) { idx in
                Button {
                    selectSample(index: idx)
                } label: {
                    HStack(spacing: 12) {
                        // お手本写真
                        if let ref = UIImage(named: photoAssets[idx]) {
                            Image(uiImage: ref)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipped()
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                )
                        } else {
                            Color.gray.opacity(0.2)
                                .frame(width: 80, height: 80)
                                .overlay(Text("No Photo"))
                        }

                        // シルエットフレーム
                        if let frame = UIImage(named: frameAssets[idx]) {
                            Image(uiImage: frame)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                )
                        } else {
                            Color.gray.opacity(0.2)
                                .frame(width: 80, height: 80)
                                .overlay(Text("No Frame"))
                        }

                        Spacer()

                        if idx == selectedSampleIndex {
                            Text("選択中")
                                .foregroundColor(.accentColor)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    // MARK: - カメラロール

    private var cameraRollSection: some View {
        Section("カメラロールから選ぶ") {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Text("写真を選択")
            }

            if let uiImage = pickedImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
            }
        }
    }

    // MARK: - サンプル選択処理

    private func selectSample(index: Int) {
        selectedSampleIndex = index
        if frameAssets.indices.contains(index) {
            frameImage = UIImage(named: frameAssets[index])
        } else {
            frameImage = nil
        }
    }

    // MARK: - カメラロール読み込み

    private func loadPickedImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                pickedImage = image
                // 現時点ではそのままフレーム画像として使う
                frameImage = image
            }
        } catch {
            errorMessage = "写真の読み込みに失敗しました"
        }
    }

    // MARK: - LiveRoomView へ遷移前の準備

    private func prepareFrameAndGo() {
        errorMessage = nil

        if useSample {
            if frameImage == nil {
                selectSample(index: selectedSampleIndex)
            }
            guard frameImage != nil else {
                errorMessage = "サンプル画像の読み込みに失敗しました"
                return
            }
            goLive = true
        } else {
            guard let picked = pickedImage else {
                errorMessage = "写真が選択されていません"
                return
            }
            frameImage = picked
            goLive = true
        }
    }
}

