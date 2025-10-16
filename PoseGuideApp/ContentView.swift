import SwiftUI

enum UserRole {
    case photographer
    case subject
}

struct ContentView: View {
    @State private var selectedRole: UserRole?
    @State private var navigate = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Text("役割を選択")
                    .font(.largeTitle.bold())

                Button("📷 撮影者として入室") {
                    selectedRole = .photographer
                    navigate = true
                }
                .buttonStyle(.borderedProminent)

                Button("🤳 被写体として入室") {
                    selectedRole = .subject
                    navigate = true
                }
                .buttonStyle(.bordered)
            }
            .navigationDestination(isPresented: $navigate) {
                if let role = selectedRole {
                    LiveRoomView(role: role)
                }
            }
        }
    }
}

