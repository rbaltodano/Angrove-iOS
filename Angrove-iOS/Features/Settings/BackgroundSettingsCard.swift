import SwiftUI

/// Which screen a background applies to; decides what the live preview sketches.
enum CanvasBackgroundSurface {
    case conversation, insightTree
}

/// One card per surface: a live preview of the current background above a single row of swatches.
struct BackgroundSettingsCard: View {
    let title: LocalizedStringResource
    let surface: CanvasBackgroundSurface
    @Binding var selection: CanvasBackgroundOption

    var body: some View {
        SettingsControlCard {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .settingsText(.label)
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                Spacer(minLength: 8)
                Text(selection.title)
                    .settingsText(.detail)
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)
                    .contentTransition(.opacity)
            }

            ZStack {
                BackgroundPreview(option: selection, surface: surface)
                    .id(selection)
                    .transition(.opacity)
            }

            HStack(spacing: 0) {
                ForEach(CanvasBackgroundOption.allCases) { option in
                    BackgroundSwatchButton(option: option, isSelected: selection == option) {
                        SettingsHaptics.playSelection()
                        withAnimation(.easeInOut(duration: 0.25)) { selection = option }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Preview

/// A small sketch of the real screen, rendered with the option's own appearance so the colors,
/// text contrast, and photo scrim are exactly what the user will get.
private struct BackgroundPreview: View {
    let option: CanvasBackgroundOption
    let surface: CanvasBackgroundSurface

    var body: some View {
        ZStack {
            CanvasBackground(option: option)
            switch surface {
            case .conversation: ConversationSketch()
            case .insightTree: TreeSketch()
            }
        }
        .canvasAppearance(option)
        .frame(height: 148)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct ConversationSketch: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What is virtue?")
                .font(.custom("LibreBaskerville-Regular", fixedSize: 15))
                .foregroundStyle(AngroveTheme.Colors.headingText)

            VStack(alignment: .leading, spacing: 7) {
                SketchLine(fraction: 1)
                SketchLine(fraction: 0.9)
                SketchLine(fraction: 0.58)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                Text("Idle")
                    .font(.custom("Figtree-Bold", fixedSize: 10))
            }
            .foregroundStyle(AngroveTheme.Colors.paragraphText)
            .padding(.horizontal, 16)
            .frame(height: 26)
            .background(AngroveTheme.Colors.canvasSecondary.opacity(0.9), in: Capsule())
            .overlay(Capsule().stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1))
            .frame(maxWidth: .infinity)
        }
        .padding(16)
    }
}

private struct SketchLine: View {
    let fraction: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(AngroveTheme.Colors.paragraphText.opacity(0.38))
                .frame(width: proxy.size.width * fraction)
        }
        .frame(height: 5)
    }
}

/// A Node Concept on the left, one of its Insights on the right, joined by the tree's 1pt connector.
private struct TreeSketch: View {
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AngroveTheme.Colors.lightGreen)
                Text("Virtue")
                    .font(.custom("Figtree-Bold", fixedSize: 15))
                    .foregroundStyle(AngroveTheme.Colors.primaryReadable)
            }

            Rectangle()
                .fill(AngroveTheme.Colors.lightGreen.opacity(0.55))
                .frame(height: 1)
                .padding(.horizontal, 10)

            HStack(spacing: 6) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Habit")
                    .font(.custom("Figtree-Bold", fixedSize: 13))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(AngroveTheme.Colors.lightGreen)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Swatches

private struct BackgroundSwatchButton: View {
    let option: CanvasBackgroundOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                BackgroundSwatchFace(option: option)
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AngroveTheme.Colors.quietBorder, lineWidth: 1))
                    .padding(4)
                    .overlay {
                        Circle()
                            .stroke(AngroveTheme.Colors.lightGreen, lineWidth: 2)
                            .opacity(isSelected ? 1 : 0)
                    }

                Text(option.title)
                    .settingsText(.detail)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(
                        isSelected ? AngroveTheme.Colors.headingText : AngroveTheme.Colors.placeholderText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(option.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct BackgroundSwatchFace: View {
    let option: CanvasBackgroundOption

    var body: some View {
        switch option {
        case .light:
            AngroveTheme.Colors.canvas.canvasAppearance(.light)
        case .dark:
            AngroveTheme.Colors.canvas.canvasAppearance(.dark)
        case .system:
            // Half light, half dark: it follows the device.
            ZStack {
                AngroveTheme.Colors.canvas.canvasAppearance(.light)
                AngroveTheme.Colors.canvas.canvasAppearance(.dark)
                    .mask(DiagonalHalf())
            }
        case .clouds:
            Image("CloudBackground")
                .resizable()
                .scaledToFill()
        }
    }
}

/// The lower-right half of a square, split along the rising diagonal.
private struct DiagonalHalf: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
