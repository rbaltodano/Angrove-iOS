//
//  LicensesSettingsView.swift
//  Angrove-iOS
//

import SwiftUI

struct LicensesSettingsView: View {
    var onSelectLicense: (BundledLicense) -> Void

    var body: some View {
        SettingsDetailScaffold(title: "Licenses") {
            VStack(alignment: .leading, spacing: 24) {
                Text("Angrove is built on openly licensed models, open-source software, open fonts, and public-domain Library texts. Thank you to their authors.")
                    .settingsParagraph()
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    .fixedSize(horizontal: false, vertical: true)

                LicenseWorksSection(title: "Models", works: AcknowledgedWork.models, onSelectLicense: onSelectLicense)
                LicenseWorksSection(title: "Software", works: AcknowledgedWork.software, onSelectLicense: onSelectLicense)
                LicenseWorksSection(title: "Fonts", works: AcknowledgedWork.fonts, onSelectLicense: onSelectLicense)
                LicenseWorksSection(title: "Library", works: AcknowledgedWork.library, onSelectLicense: onSelectLicense)
            }
        }
    }

}

private struct LicenseWorksSection: View {
    let title: LocalizedStringResource
    let works: [AcknowledgedWork]
    let onSelectLicense: (BundledLicense) -> Void

    var body: some View {
        SettingsSubsection(title: title) {
            ForEach(works) { work in
                Button {
                    SettingsHaptics.playSelection()
                    onSelectLicense(work.license)
                } label: {
                    LicenseWorkRow(work: work)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the license text")
            }
        }
    }
}

private struct LicenseWorkRow: View {
    let work: AcknowledgedWork

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(work.name)
                    .settingsText(.label)
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)

                Text(work.detail)
                    .settingsText(.paragraph)
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)

                Text("\(work.notice) \(String(localized: work.license.title)).")
                    .settingsText(.paragraph)
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .angroveIcon(.xSmall, .strong)
                .foregroundStyle(AngroveTheme.Colors.placeholderText)
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct LicenseTextView: View {
    let license: BundledLicense

    var body: some View {
        SettingsDetailScaffold(title: license.title) {
            SettingsControlCard {
                ForEach(Array(license.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .settingsText(.paragraph)
                        .foregroundStyle(AngroveTheme.Colors.paragraphText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .textSelection(.enabled)
        }
    }
}
