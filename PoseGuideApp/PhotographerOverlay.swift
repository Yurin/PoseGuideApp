import SwiftUI

struct PhotographerOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width
                let h = geo.size.height
                for i in 1...2 {
                    path.move(to: CGPoint(x: w * CGFloat(i) / 3, y: 0))
                    path.addLine(to: CGPoint(x: w * CGFloat(i) / 3, y: h))
                    path.move(to: CGPoint(x: 0, y: h * CGFloat(i) / 3))
                    path.addLine(to: CGPoint(x: w, y: h * CGFloat(i) / 3))
                }
            }
            .stroke(Color.yellow.opacity(0.7), lineWidth: 1)
        }
        .ignoresSafeArea()
    }
}

