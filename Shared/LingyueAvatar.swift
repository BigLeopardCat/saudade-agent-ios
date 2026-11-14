import SwiftUI

struct LingyueAvatar: View {
    var size: CGFloat = 56
    var body: some View {
        Image("LingyueAvatar")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("泠月喵")
    }
}
