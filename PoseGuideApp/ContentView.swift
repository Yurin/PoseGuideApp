import SwiftUI

enum UserRole {
    case photographer
    case subject
}

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Text("役割を選択")
                    .font(.largeTitle.bold())

                NavigationLink(destination: JoinRoomView(role: .photographer)) {
                    modeButton(label: "撮影者として入室", color: .blue)
                }

                NavigationLink(destination: JoinRoomView(role: .subject)) {
                    modeButton(label: "被写体として入室", color: .pink)
                }

                Spacer()
            }
            .padding()
        }
    }

    func modeButton(label: String, color: Color) -> some View {
        Text(label)
            .font(.title2)
            .foregroundColor(.white)
            .frame(width: 250, height: 60)
            .background(color)
            .cornerRadius(12)
    }
}

