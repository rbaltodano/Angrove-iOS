import SwiftUI

enum CanvasBackgroundOption: String, SettingsChoice {
    case light, dark, system, clouds

    var title: LocalizedStringResource {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "System"
        case .clouds: "Clouds"
        }
    }

    var isPhoto: Bool { self == .clouds }

    func colorScheme(following scheme: ColorScheme) -> ColorScheme {
        switch self {
        case .light: .light
        case .dark, .clouds: .dark
        case .system: scheme
        }
    }
}

/// A stationary image, independent of transcript scrolling and tree camera movement.
struct CanvasBackground: View {
    let option: CanvasBackgroundOption

    private static let scrim = Color(red: 18 / 255, green: 15 / 255, blue: 12 / 255)
    private static let scrimOpacity = 0.6

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AngroveTheme.Colors.canvas
                if option == .clouds {
                    Image("CloudBackground")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .trailing)
                        .clipped()
                    // One even scrim over the photo keeps cream text legible everywhere.
                    Self.scrim.opacity(Self.scrimOpacity)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CanvasInheritedColorSchemeKey: EnvironmentKey {
    static let defaultValue: ColorScheme? = nil
}

extension EnvironmentValues {
    fileprivate var canvasInheritedColorScheme: ColorScheme? {
        get { self[CanvasInheritedColorSchemeKey.self] }
        set { self[CanvasInheritedColorSchemeKey.self] = newValue }
    }
}

private struct CanvasAppearanceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.canvasInheritedColorScheme) private var inheritedColorScheme
    let option: CanvasBackgroundOption

    func body(content: Content) -> some View {
        let inherited = inheritedColorScheme ?? colorScheme
        content
            .environment(\.canvasInheritedColorScheme, inherited)
            .environment(\.colorScheme, option.colorScheme(following: inherited))
    }
}

extension View {
    func canvasAppearance(_ option: CanvasBackgroundOption) -> some View {
        modifier(CanvasAppearanceModifier(option: option))
    }
}
