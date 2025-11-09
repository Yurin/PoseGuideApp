import SwiftUI

struct ContentView: View {
    @State private var roomName = ""
    @State private var role: LiveRoomView.UserRole = .photographer
    @State private var go = false

    var body: some View {
        NavigationStack {
            Form {
                Section("役割") {
                    Picker("", selection: $role) {
                        Text("撮影者").tag(LiveRoomView.UserRole.photographer)
                        Text("被写体").tag(LiveRoomView.UserRole.subject)
                    }
                    .pickerStyle(.segmented)
                }
                Section("合言葉（ルーム名）") {
                    TextField("例: demo", text: $roomName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Button("入室") {
                        go = true
                    }
                    .disabled(roomName.isEmpty)
                }
            }
            .navigationDestination(isPresented: $go) {
                LiveRoomView(role: role, roomName: roomName)
            }
            .navigationTitle("PoseGuide デモ")
        }
    }
}

