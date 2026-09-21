import SwiftUI

struct AppBackgroundView: View {
    var imageName = "MainBackground"
    var tintOpacity = 0.55

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)

                Tokens.Color.paperCream
                    .opacity(tintOpacity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

extension View {
    func appBackground(
        imageName: String = "MainBackground",
        tintOpacity: Double = 0.55
g    ) -> some View {
        background {
            AppBackgroundView(imageName: imageName, tintOpacity: tintOpacity)
        }
    }
}
