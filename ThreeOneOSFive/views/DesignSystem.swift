import SwiftUI

enum AppTheme {
    static let accent = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 1.00, green: 0.64, blue: 0.42, alpha: 1.00)
                : UIColor(red: 0.85, green: 0.42, blue: 0.20, alpha: 1.00)
        }
    )
    static let pageBackground = Color(uiColor: .systemBackground)
    static let consoleBackground = Color(uiColor: .secondarySystemBackground)
    static let pageInset: CGFloat = 16
    static let rowIconSize: CGFloat = 17
    static let rowIconFrame: CGFloat = 28
    static let fileRowIconSize: CGFloat = 17
    static let fileRowIconFrame: CGFloat = 30
    static let fileRowHeight: CGFloat = 60
    static let appIconSize: CGFloat = 32
    static let emptyIconSize: CGFloat = 30
    static let selectionIconSize: CGFloat = 18
    static let contentCardCornerRadius: CGFloat = 20
    static let contentCardInset: CGFloat = 16
    static let contentCardPadding: CGFloat = 16

    static func animatedTextColor(at date: Date) -> Color {
        let palette: [UIColor] = [
            UIColor(red: 0.15, green: 0.42, blue: 1.00, alpha: 1.00),
            UIColor(red: 0.55, green: 0.20, blue: 1.00, alpha: 1.00),
            UIColor(red: 1.00, green: 0.16, blue: 0.22, alpha: 1.00),
            UIColor(red: 0.12, green: 0.78, blue: 0.32, alpha: 1.00),
            UIColor(red: 1.00, green: 0.76, blue: 0.05, alpha: 1.00)
        ]
        let cycleDuration = 20.0
        let progress = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
            * Double(palette.count)
        let lowerIndex = Int(progress.rounded(.down)) % palette.count
        let upperIndex = (lowerIndex + 1) % palette.count
        let fraction = CGFloat(progress - Double(Int(progress.rounded(.down))))
        let first = palette[lowerIndex]
        let second = palette[upperIndex]
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0
        first.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        second.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(
            red: Double(r1 + (r2 - r1) * fraction),
            green: Double(g1 + (g2 - g1) * fraction),
            blue: Double(b1 + (b2 - b1) * fraction),
            opacity: Double(a1 + (a2 - a1) * fraction)
        )
    }
}

enum VisualPreferences {
    static let animatedColorsKey = "snapchat.visual.animatedColors"
    static let appearanceKey = "snapchat.visual.appearance"
}

enum VisualAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Sistema"
        case .light: return "Claro"
        case .dark: return "Escuro"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AnimatedTextAppearance: ViewModifier {
    @AppStorage(VisualPreferences.animatedColorsKey) private var animatedColorsEnabled = true

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 0.08)) { timeline in
            content
                .foregroundStyle(
                    animatedColorsEnabled
                        ? AppTheme.animatedTextColor(at: timeline.date)
                        : AppTheme.accent
                )
                .fontWeight(.bold)
        }
    }
}

extension View {
    func animatedTextAppearance() -> some View {
        modifier(AnimatedTextAppearance())
    }
}

struct SnapchatAnimatedBackground: View {
    @AppStorage(VisualPreferences.animatedColorsKey) private var animatedColorsEnabled = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { timeline in
            let first = animatedColorsEnabled
                ? AppTheme.animatedTextColor(at: timeline.date)
                : AppTheme.accent
            let second = animatedColorsEnabled
                ? AppTheme.animatedTextColor(at: timeline.date.addingTimeInterval(5))
                : AppTheme.accent.opacity(0.65)
            ZStack {
                LinearGradient(
                    colors: [first.opacity(0.22), second.opacity(0.10), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(first.opacity(0.10))
                    .frame(width: 260, height: 260)
                    .blur(radius: 50)
                    .offset(x: 150, y: -260)
                Circle()
                    .fill(second.opacity(0.08))
                    .frame(width: 220, height: 220)
                    .blur(radius: 45)
                    .offset(x: -150, y: 260)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

struct SnapchatLaunchView: View {
    let onFinished: () -> Void
    @State private var isVisible = false
    @State private var didFinish = false

    var body: some View {
        ZStack {
            SnapchatAnimatedBackground()
                .background(Color.black)
            VStack(spacing: 18) {
                AppLogo(size: 92)
                    .scaleEffect(isVisible ? 1 : 0.72)
                    .opacity(isVisible ? 1 : 0)
                Text("Snapchat")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(isVisible ? 1 : 0)
            }
        }
        .onAppear {
            guard !didFinish else { return }
            didFinish = true
            withAnimation(.spring(response: 0.65, dampingFraction: 0.78)) {
                isVisible = true
            }
            Task {
                try? await Task.sleep(nanoseconds: 1_450_000_000)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        onFinished()
                    }
                }
            }
        }
    }
}

struct SnapchatPatchIcon: View {
    let item: PatchLibraryItem

    var body: some View {
        Image("PatchCardIcon")
            .resizable()
            .scaledToFill()
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.7)
            }
            .shadow(color: Color.black.opacity(0.35), radius: 10, y: 5)
        .accessibilityHidden(true)
    }
}

struct SnapchatActionButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isDestructive ? Color.red.opacity(0.86) : AppTheme.accent)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: (isDestructive ? Color.red : AppTheme.accent).opacity(0.25), radius: 12, y: 6)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct AppCardBorder: View {
    var body: some View {
        RoundedRectangle(
            cornerRadius: AppTheme.contentCardCornerRadius,
            style: .continuous
        )
        .strokeBorder(
            Color(uiColor: .separator).opacity(0.22),
            lineWidth: 0.5
        )
        .accessibilityHidden(true)
    }
}

struct AppRowIcon: View {
    let systemName: String
    var tint: Color = AppTheme.accent
    var symbolSize: CGFloat = AppTheme.rowIconSize
    var frameSize: CGFloat = AppTheme.rowIconFrame

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.12))
            Image(systemName: systemName)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: frameSize, height: frameSize)
        .accessibilityHidden(true)
    }
}

struct AppSearchField: View {
    @Binding var text: String
    let prompt: String
    let clearLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(prompt, text: $text)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clearLabel)
            }
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 36)
        .background(
            Color(uiColor: .secondarySystemFill),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.horizontal, AppTheme.pageInset)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct AppLogo: View {
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let icon = UIImage(named: "AppIcon60x60")
                ?? Bundle.main.path(forResource: "AppIcon60x60@2x", ofType: "png").flatMap(UIImage.init(contentsOfFile:))
                ?? UIImage(named: "AppIcon") {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}
