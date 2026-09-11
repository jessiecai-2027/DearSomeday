import SwiftUI

struct AppBackgroundView: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("MainBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)

                Tokens.Color.paperCream
                    .opacity(0.30)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

extension View {
    func appBackground() -> some View {
        background {
            AppBackgroundView()
        }
    }
}
