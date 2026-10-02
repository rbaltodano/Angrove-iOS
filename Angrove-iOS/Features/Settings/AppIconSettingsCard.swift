import SwiftUI
import UIKit

enum AppIconOption: String, CaseIterable, Identifiable {
    case light = "AngroveLightIcon"
    case dark = "AngroveDarkIcon"

    var id: Self { self }
    var previewAsset: String { rawValue + "Preview" }
    var title: LocalizedStringResource {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var accessibilityTitle: LocalizedStringResource {
        switch self {
        case .light: "Light app icon"
        case .dark: "Dark app icon"
        }
    }
}

/// iOS persists the actual icon choice; only mark a choice after the system accepts it.
struct AppIconSettingsCard: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedIcon = UIApplication.shared.alternateIconName.flatMap(AppIconOption.init(rawValue:))
    @State private var isChanging = false
    @State private var errorMessage: String?

    var body: some View {
        AppIconSelectionCard(selectedIcon: selectedIcon, isChanging: isChanging) { option in
            Task { await select(option) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshSelection() }
        }
        .alert("Couldn’t Change App Icon", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func refreshSelection() {
        selectedIcon = UIApplication.shared.alternateIconName.flatMap(AppIconOption.init(rawValue:))
    }

    private func select(_ option: AppIconOption) async {
        guard !isChanging, selectedIcon != option else { return }
        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = String(localized: "App icon changes aren’t available on this device.")
            return
        }
        isChanging = true
        defer { isChanging = false }
        do {
            try await UIApplication.shared.setAlternateIconName(option.rawValue)
            refreshSelection()
            await SettingsHaptics.playDoubleSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AppIconSelectionCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let selectedIcon: AppIconOption?
    var isChanging = false
    let onSelect: (AppIconOption) -> Void

    var body: some View {
        (dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 24))
            : AnyLayout(HStackLayout(spacing: 0))) {
            ForEach(AppIconOption.allCases) { option in
                AppIconChoiceButton(option: option, isSelected: selectedIcon == option) {
                    onSelect(option)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .disabled(isChanging)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            AnimatedDotGridBackground(settledOffset: .zero, settledScale: 1)
                .background(AngroveTheme.Colors.canvasSecondary)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(AngroveTheme.Colors.brownBorder, lineWidth: 1)
        }
    }
}

private struct AppIconChoiceButton: View {
    let option: AppIconOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(option.previewAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .accessibilityHidden(true)

                HStack(spacing: 6) {
                    Text(option.title)
                        .font(AngroveTheme.Typography.settingsLabel)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .opacity(isSelected ? 1 : 0)
                }
                .foregroundStyle(AngroveTheme.Colors.lightGreen)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(option.accessibilityTitle))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
