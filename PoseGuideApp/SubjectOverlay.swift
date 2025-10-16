import SwiftUI

struct SubjectOverlay: View {
    var body: some View {
        VStack {
            Spacer()
            Text("カメラ目線で！")
                .font(.title2.bold())
                .foregroundColor(.white)
                .padding(.bottom, 40)
        }
        .shadow(radius: 5)
    }
}

