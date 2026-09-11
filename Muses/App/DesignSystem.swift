import SwiftUI

enum MusesTheme {
    static let background = Color(red: 0.988, green: 0.976, blue: 0.949)
    static let surface = Color(red: 1.0, green: 0.997, blue: 0.984)
    static let ink = Color(red: 0.14, green: 0.13, blue: 0.12)
    static let secondaryInk = Color(red: 0.46, green: 0.43, blue: 0.39)
    static let coral = Color(red: 0.24, green: 0.68, blue: 0.92)
    static let coralSoft = Color(red: 0.84, green: 0.95, blue: 1.0)
    static let green = Color(red: 0.39, green: 0.64, blue: 0.23)
    static let greenSoft = Color(red: 0.92, green: 0.96, blue: 0.86)
    static let success = green
    static let successSoft = greenSoft
    static let amber = Color(red: 0.91, green: 0.56, blue: 0.08)
    static let amberSoft = Color(red: 1.0, green: 0.95, blue: 0.81)
    static let line = Color(red: 0.88, green: 0.85, blue: 0.79)
    static let cardRadius: CGFloat = 24
}

struct MusesBackground: View {
    var body: some View {
        MusesTheme.background
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(MusesTheme.coralSoft.opacity(0.45))
                    .frame(width: 220, height: 220)
                    .blur(radius: 70)
                    .offset(x: 80, y: -80)
                    .accessibilityHidden(true)
            }
            .ignoresSafeArea()
    }
}

struct MusesLogo: View {
    var compact = false

    var body: some View {
        HStack(spacing: 2) {
            Text("Muses")
                .font(.system(size: compact ? 27 : 38, weight: .bold, design: .rounded))
                .foregroundStyle(MusesTheme.ink)
            Image(systemName: "sparkle")
                .font(.system(size: compact ? 11 : 14, weight: .bold))
                .foregroundStyle(MusesTheme.coral)
                .offset(y: compact ? -8 : -12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Muses")
    }
}

struct SurfaceCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .background(MusesTheme.surface, in: RoundedRectangle(cornerRadius: MusesTheme.cardRadius, style: .continuous))
            .shadow(color: Color.brown.opacity(0.07), radius: 18, y: 8)
    }
}

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var isLoading = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let icon {
                    Image(systemName: icon)
                }
                Text(title).fontWeight(.bold)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [MusesTheme.coral, Color(red: 0.42, green: 0.80, blue: 1.0)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .opacity(disabled ? 0.42 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled || isLoading)
    }
}

struct SecondaryButton: View {
    let title: String
    var icon: String? = nil
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .foregroundStyle(destructive ? MusesTheme.coral : MusesTheme.ink)
            .background(MusesTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(destructive ? MusesTheme.coral.opacity(0.5) : MusesTheme.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct PageHeader: View {
    let title: String
    var subtitle: String? = nil
    var step: String? = nil
    var backAction: (() -> Void)? = nil
    var trailing: AnyView? = nil

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                MusesLogo(compact: true)
                HStack {
                    if let backAction {
                        Button(action: backAction) {
                            Image(systemName: "chevron.left")
                                .font(.headline.weight(.bold))
                                .frame(width: 44, height: 44)
                                .foregroundStyle(MusesTheme.ink)
                                .background(.white.opacity(0.7), in: Circle())
                        }
                        .accessibilityLabel("返回")
                    }
                    Spacer()
                    if let trailing { trailing }
                }
            }
            if let step {
                Text(step)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(MusesTheme.coral)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.72), in: Capsule())
            }
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(MusesTheme.ink)
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(MusesTheme.secondaryInk)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}

struct InfoBanner: View {
    let text: String
    var kind: Kind = .success

    enum Kind { case success, warning, neutral }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
            Text(text)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(foreground)
        .padding(16)
        .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var icon: String {
        switch kind { case .success: "checkmark.seal.fill"; case .warning: "exclamationmark.shield.fill"; case .neutral: "info.circle.fill" }
    }

    private var foreground: Color {
        switch kind { case .success: MusesTheme.green; case .warning: MusesTheme.amber; case .neutral: MusesTheme.secondaryInk }
    }

    private var background: Color {
        switch kind { case .success: MusesTheme.greenSoft; case .warning: MusesTheme.amberSoft; case .neutral: MusesTheme.surface }
    }
}

struct StatusPill: View {
    let text: String
    var tone: Tone = .success
    enum Tone { case success, warning, failure, neutral }

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color.opacity(0.11), in: Capsule())
    }

    private var color: Color {
        switch tone { case .success: MusesTheme.green; case .warning: MusesTheme.amber; case .failure: MusesTheme.coral; case .neutral: MusesTheme.secondaryInk }
    }
}

extension View {
    func musesPage() -> some View {
        self
            .foregroundStyle(MusesTheme.ink)
            .background(MusesBackground())
            .tint(MusesTheme.coral)
    }
}

#if DEBUG
#Preview("Design System") {
    ScrollView {
        VStack(spacing: 16) {
            PageHeader(title: "共享组件", subtitle: "Muses 视觉系统", step: "Preview")
            SurfaceCard {
                VStack(spacing: 12) {
                    StatusPill(text: "已完成", tone: .success)
                    InfoBanner(text: "这是共享状态提示组件。", kind: .neutral)
                    PrimaryButton(title: "主操作", icon: "sparkles") {}
                    SecondaryButton(title: "次操作", icon: "arrow.clockwise") {}
                }
            }
        }
        .padding(20)
    }
    .musesPage()
}
#endif
