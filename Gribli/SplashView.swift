import SwiftUI

struct SplashView: View {
    let onPlay: () -> Void

    @State private var titleOffset: CGFloat = -40
    @State private var titleOpacity: Double = 0
    @State private var iconOffset: CGFloat = -80
    @State private var iconScale: CGFloat = 0.6
    @State private var iconOpacity: Double = 0
    @State private var buttonOffset: CGFloat = 60
    @State private var buttonOpacity: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var dismissScale: CGFloat = 1.0
    @State private var dismissOpacity: Double = 1.0
    @Environment(\.colorScheme) private var colorScheme

    private var bgColor: Color { Palette.background(for: colorScheme) }
    private var textColor: Color { Palette.text(for: colorScheme) }

    var body: some View {
        VStack(spacing: 40) {
            Text("Gribli")
                .font(.system(size: 42, weight: .heavy))
                .foregroundStyle(textColor)
                .offset(y: titleOffset)
                .opacity(titleOpacity)

            if let icon = Bundle.main.icon {
                Image(uiImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                    .offset(y: iconOffset)
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)
            }

            Button(action: dismiss) {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.title2)
                    Text("Play")
                        .font(.title2.bold())
                }
                .foregroundStyle(bgColor)
                .padding(.horizontal, 36)
                .padding(.vertical, 16)
                .background(textColor, in: Capsule())
                .scaleEffect(pulseScale)
            }
            .padding(.top, 10)
            .offset(y: buttonOffset)
            .opacity(buttonOpacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bgColor.ignoresSafeArea())
        .scaleEffect(dismissScale)
        .opacity(dismissOpacity)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.4).delay(0.1)) {
                titleOffset = 0
                titleOpacity = 1.0
            }
            withAnimation(.spring(duration: 0.7, bounce: 0.5)) {
                iconOffset = 0
                iconScale = 1.0
                iconOpacity = 1.0
            }
            withAnimation(.spring(duration: 0.5, bounce: 0.4).delay(0.35)) {
                buttonOffset = 0
                buttonOpacity = 1.0
            }
            withAnimation(
                .easeInOut(duration: 1.2)
                .repeatForever(autoreverses: true)
                .delay(0.9)
            ) {
                pulseScale = 1.1
            }
        }
    }

    private func playHaptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func dismiss() {
        playHaptic()
        withAnimation(.easeOut(duration: 0.45)) {
            dismissScale = 0.85
            dismissOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            onPlay()
        }
    }
}

private extension Bundle {
    var icon: UIImage? {
        guard let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last else { return nil }
        return UIImage(named: name)
    }
}
