import SwiftUI

enum SAVETheme {
    static let canvas = Color(red: 0.965, green: 0.976, blue: 0.988)
    static let surface = Color.white
    static let ink = Color(red: 0.055, green: 0.071, blue: 0.090)
    static let muted = Color(red: 0.390, green: 0.425, blue: 0.470)
    static let accent = Color(red: 0.000, green: 0.690, blue: 0.780)
    static let warning = Color(red: 0.925, green: 0.545, blue: 0.080)
    static let success = Color(red: 0.090, green: 0.610, blue: 0.330)
    static let hairline = Color.black.opacity(0.075)

    static let controlRadius: CGFloat = 12
    static let surfaceRadius: CGFloat = 16
    static let largeSurfaceRadius: CGFloat = 20
}

struct SAVEPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let content = configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.65))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .padding(.horizontal, 18)
            .contentShape(.rect(cornerRadius: SAVETheme.controlRadius))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)

        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular
                        .tint(isEnabled ? SAVETheme.accent : Color.secondary.opacity(0.45))
                        .interactive(),
                    in: .rect(cornerRadius: SAVETheme.controlRadius)
                )
        } else {
            content
                .background(
                    isEnabled ? SAVETheme.accent : Color.secondary.opacity(0.45),
                    in: RoundedRectangle(cornerRadius: SAVETheme.controlRadius, style: .continuous)
                )
                .shadow(color: SAVETheme.accent.opacity(isEnabled ? 0.16 : 0), radius: 12, y: 6)
        }
    }
}

struct SAVESecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let content = configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? SAVETheme.ink : SAVETheme.muted.opacity(0.65))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .padding(.horizontal, 18)
            .contentShape(.rect(cornerRadius: SAVETheme.controlRadius))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)

        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.interactive(),
                    in: .rect(cornerRadius: SAVETheme.controlRadius)
                )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: SAVETheme.controlRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: SAVETheme.controlRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 1)
                }
        }
    }
}

struct SAVECompactButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(tint.opacity(configuration.isPressed ? 0.16 : 0.09), in: Capsule())
            .overlay {
                Capsule().stroke(tint.opacity(0.16), lineWidth: 0.5)
            }
    }
}

struct SAVEIconBadge: View {
    let symbol: String
    var tint: Color = SAVETheme.accent
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct SAVESectionTitle: View {
    let title: String
    var action: String?
    var perform: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(SAVETheme.ink)
            Spacer()
            if let action, let perform {
                Button(action, action: perform)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SAVETheme.accent)
            }
        }
    }
}

struct SAVELedgerDivider: View {
    var body: some View {
        Rectangle()
            .fill(SAVETheme.hairline)
            .frame(height: 0.5)
    }
}

private struct SAVESolidSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                SAVETheme.surface,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.045), radius: 14, y: 7)
    }
}

private struct SAVEGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.92), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.07), radius: 16, y: 8)
        }
    }
}

extension View {
    func saveSolidSurface(
        cornerRadius: CGFloat = SAVETheme.surfaceRadius,
        padding: CGFloat = 16
    ) -> some View {
        modifier(SAVESolidSurfaceModifier(cornerRadius: cornerRadius, padding: padding))
    }

    func saveGlassSurface(
        cornerRadius: CGFloat = SAVETheme.surfaceRadius,
        interactive: Bool = false
    ) -> some View {
        modifier(SAVEGlassSurfaceModifier(cornerRadius: cornerRadius, interactive: interactive))
    }

    func saveDocumentBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(SAVETheme.canvas)
            .tint(SAVETheme.accent)
    }
}
