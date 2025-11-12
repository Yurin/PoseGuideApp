import SwiftUI

struct JoinRoomView: View {
    let role: LiveRoomView.UserRole     
    @State private var roomName: String = ""
    @State private var navigate = false

    var body: some View {
        VStack(spacing: 30) {
            Text(role == .photographer ? "撮影者として入室" : "被写体として入室")
                .font(.largeTitle.bold())
                .padding(.top, 50)

            VStack(alignment: .leading, spacing: 10) {
                Text("ルーム合言葉を入力")
                    .font(.headline)

                TextField("例: yuri001", text: $roomName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 40)
                    .textInputAutocapitalization(.never) // iOS 15+
                    .autocorrectionDisabled()
            }

            Button {
                if !roomName.isEmpty { navigate = true }
            } label: {
                Text("入室する")
                    .frame(width: 200, height: 50)
                    .background(roomName.isEmpty ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(roomName.isEmpty)

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .navigationDestination(isPresented: $navigate) {
            LiveRoomView(role: role, roomName: roomName)
        }
    }
}

