import SwiftUI

// MARK: - Noot Cyberpunk Theme

struct NootTheme {
    // MARK: - Primary Colors
    static let cyan = Color(red: 0.0, green: 1.0, blue: 1.0)           // #00FFFF
    static let magenta = Color(red: 1.0, green: 0.0, blue: 1.0)        // #FF00FF
    static let pink = Color(red: 1.0, green: 0.4, blue: 0.8)           // #FF66CC
    static let purple = Color(red: 0.6, green: 0.2, blue: 1.0)         // #9933FF

    // MARK: - Background Colors
    static let background = Color(red: 0.05, green: 0.05, blue: 0.1)   // Near black with blue tint
    static let backgroundLight = Color(red: 0.08, green: 0.08, blue: 0.15)
    static let surface = Color(red: 0.1, green: 0.1, blue: 0.18)       // Elevated surfaces
    static let surfaceLight = Color(red: 0.15, green: 0.15, blue: 0.25)

    // MARK: - Text Colors
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.6, green: 0.65, blue: 0.8)
    static let textMuted = Color(red: 0.4, green: 0.45, blue: 0.6)

    // MARK: - Semantic Colors
    static let success = Color(red: 0.0, green: 1.0, blue: 0.6)        // Neon green
    static let warning = Color(red: 1.0, green: 0.8, blue: 0.0)        // Neon yellow
    static let error = Color(red: 1.0, green: 0.3, blue: 0.4)          // Neon red
    static let recording = Color(red: 1.0, green: 0.2, blue: 0.4)      // Hot pink for recording

    // MARK: - Gradients
    static let primaryGradient = LinearGradient(
        colors: [cyan, magenta],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let backgroundGradient = LinearGradient(
        colors: [background, Color(red: 0.08, green: 0.05, blue: 0.15)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let glowGradient = LinearGradient(
        colors: [cyan.opacity(0.8), purple.opacity(0.8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Fonts
    static let monoFont = Font.system(.body, design: .monospaced)
    static let monoFontSmall = Font.system(.caption, design: .monospaced)
    static let monoFontLarge = Font.system(.title3, design: .monospaced)
    static let monoFontTitle = Font.system(.title, design: .monospaced).weight(.bold)

    // MARK: - Effects
    static let glowRadius: CGFloat = 8
    static let subtleGlowRadius: CGFloat = 4
    static let borderWidth: CGFloat = 1
}

// MARK: - Glow Effect Modifier

struct NeonGlow: ViewModifier {
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.8), radius: radius / 2, x: 0, y: 0)
            .shadow(color: color.opacity(0.5), radius: radius, x: 0, y: 0)
            .shadow(color: color.opacity(0.3), radius: radius * 1.5, x: 0, y: 0)
    }
}

extension View {
    func neonGlow(_ color: Color = NootTheme.cyan, radius: CGFloat = NootTheme.glowRadius) -> some View {
        modifier(NeonGlow(color: color, radius: radius))
    }

    func cyanGlow(radius: CGFloat = NootTheme.glowRadius) -> some View {
        modifier(NeonGlow(color: NootTheme.cyan, radius: radius))
    }

    func magentaGlow(radius: CGFloat = NootTheme.glowRadius) -> some View {
        modifier(NeonGlow(color: NootTheme.magenta, radius: radius))
    }
}

// MARK: - Chromatic Aberration Text

struct ChromaticText: View {
    let text: String
    let font: Font
    let offset: CGFloat

    init(_ text: String, font: Font = NootTheme.monoFontLarge, offset: CGFloat = 1.5) {
        self.text = text
        self.font = font
        self.offset = offset
    }

    var body: some View {
        ZStack {
            // Cyan layer (offset left)
            Text(text)
                .font(font)
                .foregroundColor(NootTheme.cyan)
                .offset(x: -offset, y: 0)
                .blendMode(.screen)

            // Magenta layer (offset right)
            Text(text)
                .font(font)
                .foregroundColor(NootTheme.magenta)
                .offset(x: offset, y: 0)
                .blendMode(.screen)

            // White center layer
            Text(text)
                .font(font)
                .foregroundColor(.white)
        }
    }
}

// MARK: - Neon Border

struct NeonBorder: ViewModifier {
    let color: Color
    let width: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color, lineWidth: width)
                    .neonGlow(color, radius: 4)
            )
    }
}

extension View {
    func neonBorder(_ color: Color = NootTheme.cyan, width: CGFloat = 1) -> some View {
        modifier(NeonBorder(color: color, width: width))
    }
}

// MARK: - Scan Lines Effect

struct ScanLines: View {
    let lineSpacing: CGFloat
    let opacity: Double

    init(spacing: CGFloat = 4, opacity: Double = 0.1) {
        self.lineSpacing = spacing
        self.opacity = opacity
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: lineSpacing) {
                ForEach(0..<Int(geometry.size.height / lineSpacing), id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 1)
                }
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}

// MARK: - Themed Button Style

struct NeonButtonStyle: ButtonStyle {
    let color: Color

    init(color: Color = NootTheme.cyan) {
        self.color = color
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NootTheme.monoFontSmall)
            .foregroundColor(configuration.isPressed ? color : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? color.opacity(0.2) : NootTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(configuration.isPressed ? 1 : 0.6), lineWidth: 1)
            )
            .neonGlow(color, radius: configuration.isPressed ? 6 : 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Themed Text Field Style

struct NeonTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(NootTheme.monoFont)
            .foregroundColor(NootTheme.textPrimary)
            .padding(10)
            .background(NootTheme.surface)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(NootTheme.cyan.opacity(0.4), lineWidth: 1)
            )
    }
}

// MARK: - Tag/Chip Style

struct NeonTag: View {
    let text: String
    let icon: String?
    let color: Color
    let onRemove: (() -> Void)?

    init(_ text: String, icon: String? = nil, color: Color = NootTheme.cyan, onRemove: (() -> Void)? = nil) {
        self.text = text
        self.icon = icon
        self.color = color
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(text)
                .font(NootTheme.monoFontSmall)

            if let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(color.opacity(0.5), lineWidth: 0.5)
        )
    }
}

// MARK: - Status Indicator

struct NeonStatusIndicator: View {
    enum Status {
        case active, inactive, recording, warning
    }

    let status: Status
    let label: String?

    var color: Color {
        switch status {
        case .active: return NootTheme.success
        case .inactive: return NootTheme.textMuted
        case .recording: return NootTheme.recording
        case .warning: return NootTheme.warning
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .neonGlow(color, radius: 4)

            if let label = label {
                Text(label)
                    .font(NootTheme.monoFontSmall)
                    .foregroundColor(color)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ChromaticText("NOOT", font: NootTheme.monoFontTitle, offset: 2)

        Text("System Online...")
            .font(NootTheme.monoFont)
            .foregroundColor(NootTheme.cyan)
            .cyanGlow()

        HStack {
            NeonTag("domain", icon: "folder", color: NootTheme.cyan)
            NeonTag("workstream", icon: "arrow.triangle.branch", color: NootTheme.magenta)
        }

        HStack {
            NeonStatusIndicator(status: .active, label: "SAVED")
            NeonStatusIndicator(status: .recording, label: "REC")
        }

        Button("EXECUTE") {}
            .buttonStyle(NeonButtonStyle())

        Button("TERMINATE") {}
            .buttonStyle(NeonButtonStyle(color: NootTheme.magenta))
    }
    .padding(40)
    .background(NootTheme.background)
    .preferredColorScheme(.dark)
}
