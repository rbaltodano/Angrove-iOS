//
//  LicensesSettingsView.swift
//  Angrove-iOS
//

import SwiftUI

/// A bundled license text. Each one is a plain-text resource in `Resources/Licenses`.
enum BundledLicense: String, Hashable, CaseIterable {
    case apache2 = "license-apache-2.0"
    case onnxRuntimeMIT = "license-onnxruntime-mit"
    case figtreeOFL = "license-figtree-ofl"
    case libreBaskervilleOFL = "license-libre-baskerville-ofl"

    var title: LocalizedStringResource {
        switch self {
        case .apache2: "Apache License 2.0"
        case .onnxRuntimeMIT: "MIT License"
        case .figtreeOFL, .libreBaskervilleOFL: "SIL Open Font License 1.1"
        }
    }

    /// The license text with hard-wrapped lines joined into paragraphs, so it reflows to the
    /// phone's width instead of breaking every 70 characters.
    var paragraphs: [String] {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text
            .components(separatedBy: "\n\n")
            .map { block in
                block
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !$0.allSatisfy { $0 == "-" } }
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
    }
}

/// Software, models and fonts that ship inside Angrove, with the notice each license asks for.
struct AcknowledgedWork: Identifiable {
    let name: String
    let detail: LocalizedStringResource
    let notice: String
    let license: BundledLicense

    var id: String { name }

    static let models: [AcknowledgedWork] = [
        AcknowledgedWork(
            name: "Gemma 4 E4B",
            detail: "Answers, titles, and Insights",
            notice: "Copyright Google LLC.",
            license: .apache2
        ),
        AcknowledgedWork(
            name: "all-MiniLM-L6-v2",
            detail: "Source retrieval and Insight relationships",
            notice: "Copyright the Sentence Transformers authors.",
            license: .apache2
        ),
        AcknowledgedWork(
            name: "Paradee-8M",
            detail: "Read aloud",
            notice: "Copyright Sahil Mahendrakar. Distilled from Kokoro-82M, copyright hexgrad.",
            license: .apache2
        )
    ]

    static let software: [AcknowledgedWork] = [
        AcknowledgedWork(
            name: "LiteRT-LM",
            detail: "On-device model runtime",
            notice: "Copyright Google LLC.",
            license: .apache2
        ),
        AcknowledgedWork(
            name: "ONNX Runtime",
            detail: "Speech runtime",
            notice: "Copyright (c) Microsoft Corporation.",
            license: .onnxRuntimeMIT
        ),
        AcknowledgedWork(
            name: "MisakiSwift",
            detail: "Pronunciation for read aloud",
            notice: "Copyright mlalma. Based on misaki, copyright hexgrad. Modified for Angrove.",
            license: .apache2
        )
    ]

    static let fonts: [AcknowledgedWork] = [
        AcknowledgedWork(
            name: "Libre Baskerville",
            detail: "Serif typeface",
            notice: "Copyright 2012 The Libre Baskerville Project Authors.",
            license: .libreBaskervilleOFL
        ),
        AcknowledgedWork(
            name: "Figtree",
            detail: "Sans-serif typeface",
            notice: "Copyright 2022 The Figtree Project Authors.",
            license: .figtreeOFL
        )
    ]
}

struct LicensesSettingsView: View {
    var onSelectLicense: (BundledLicense) -> Void

    var body: some View {
        SettingsDetailScaffold(title: "Licenses") {
            VStack(alignment: .leading, spacing: 24) {
                Text("Angrove is built on openly licensed models, open-source software, and open fonts. Thank you to their authors.")
                    .settingsGuideParagraph()
                    .foregroundStyle(AngroveTheme.Colors.paragraphText)
                    .fixedSize(horizontal: false, vertical: true)

                section("Models", works: AcknowledgedWork.models)
                section("Software", works: AcknowledgedWork.software)
                section("Fonts", works: AcknowledgedWork.fonts)
            }
        }
    }

    private func section(_ title: LocalizedStringResource, works: [AcknowledgedWork]) -> some View {
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
                    .settingsText(.detail)
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)

                Text("\(work.notice) \(String(localized: work.license.title)).")
                    .settingsText(.detail)
                    .foregroundStyle(AngroveTheme.Colors.placeholderText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
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
                        .font(AngroveTheme.Typography.settingsBody)
                        .lineSpacing(AngroveTheme.Typography.settingsGuideLineSpacing)
                        .foregroundStyle(AngroveTheme.Colors.paragraphText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .textSelection(.enabled)
        }
    }
}
