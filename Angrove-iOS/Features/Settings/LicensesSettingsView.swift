//
//  LicensesSettingsView.swift
//  Angrove-iOS
//

import SwiftUI

/// A bundled license text. Each one is a plain-text resource in `Resources/Licenses`.
enum BundledLicense: String, Hashable, CaseIterable {
    case libraryPublicDomain = "license-library-public-domain"
    case apache2 = "license-apache-2.0"
    case onnxRuntimeMIT = "license-onnxruntime-mit"
    case figtreeOFL = "license-figtree-ofl"
    case libreBaskervilleOFL = "license-libre-baskerville-ofl"

    var title: LocalizedStringResource {
        switch self {
        case .libraryPublicDomain: "Public Domain"
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

/// Library editions, software, models and fonts that ship inside Angrove, with the notice each license asks for.
struct AcknowledgedWork: Identifiable {
    let name: String
    let detail: LocalizedStringResource
    let notice: String
    let license: BundledLicense

    var id: String { name }

    /// The 37 editions approved as `confirmed_pd` in the corpus manifest.
    /// Keep this explicit: a newly bundled work must have its rights reviewed before listing it.
    static let library: [AcknowledgedWork] = [
        libraryWork(id: "irenaeus-against-heresies", title: "Against Heresies"),
        libraryWork(id: "adam-smith-wealth-of-nations", title: "An Inquiry into the Nature and Causes of the Wealth of Nations"),
        libraryWork(id: "tacitus-annals-histories", title: "Annals and Histories"),
        libraryWork(id: "josephus-antiquities", title: "Antiquities of the Jews / The Jewish War"),
        libraryWork(id: "augsburg-confession", title: "Augsburg Confession (1530)"),
        libraryWork(id: "baltimore-catechism-3", title: "Baltimore Catechism No. 3 (1921 historical edition)"),
        libraryWork(id: "belgic-confession", title: "Belgic Confession (1561)"),
        libraryWork(id: "council-of-trent", title: "Canons and Decrees of the Council of Trent"),
        libraryWork(id: "roman-catechism-donovan", title: "Catechism of the Council of Trent (Donovan, 1829)"),
        libraryWork(id: "aristotle-categories", title: "Categories"),
        libraryWork(id: "augustine-city-of-god", title: "City of God"),
        libraryWork(id: "augustine-confessions", title: "Confessions"),
        libraryWork(id: "us-constitution", title: "Constitution of the United States of America"),
        libraryWork(id: "us-declaration-of-independence", title: "Declaration of Independence"),
        libraryWork(id: "eusebius-ecclesiastical-history", title: "Ecclesiastical History"),
        libraryWork(id: "bede-ecclesiastical-history", title: "Ecclesiastical History of the English People"),
        libraryWork(id: "ecumenical-creeds-schaff", title: "Ecumenical Creeds (Schaff, Creeds of Christendom II)"),
        libraryWork(id: "justin-martyr-first-apology", title: "First Apology"),
        libraryWork(id: "heidelberg-catechism", title: "Heidelberg Catechism (1563)"),
        libraryWork(id: "livy-history-of-rome", title: "History of Rome"),
        libraryWork(id: "thucydides-peloponnesian-war", title: "History of the Peloponnesian War"),
        libraryWork(id: "magna-carta", title: "Magna Carta (1215)"),
        libraryWork(id: "aristotle-metaphysics", title: "Metaphysics"),
        libraryWork(id: "aristotle-nicomachean-ethics", title: "Nicomachean Ethics"),
        libraryWork(id: "athanasius-on-incarnation", title: "On the Incarnation"),
        libraryWork(id: "plutarch-parallel-lives", title: "Parallel Lives"),
        libraryWork(id: "anselm-proslogion", title: "Proslogion"),
        libraryWork(id: "summa-theologica", title: "Summa Theologica"),
        libraryWork(id: "boethius-consolation", title: "The Consolation of Philosophy"),
        libraryWork(id: "didache", title: "The Didache (Teaching of the Twelve Apostles)"),
        libraryWork(id: "herodotus-histories", title: "The Histories"),
        libraryWork(id: "gibbon-decline-and-fall", title: "The History of the Decline and Fall of the Roman Empire"),
        libraryWork(id: "machiavelli-the-prince", title: "The Prince"),
        libraryWork(id: "seven-ecumenical-councils", title: "The Seven Ecumenical Councils (Percival, 1900; texts and historical notes)"),
        libraryWork(id: "thirty-nine-articles", title: "Thirty-Nine Articles (1571)"),
        libraryWork(id: "westminster-confession", title: "Westminster Confession of Faith (1646)"),
        libraryWork(id: "web-bible", title: "World English Bible")
    ]

    private static func libraryWork(id: String, title: String) -> AcknowledgedWork {
        let author = id == "web-bible"
            ? "World English Bible translators and editors"
            : LibraryWorkAttribution.author(workID: id) ?? "Unknown author"
        return AcknowledgedWork(
            name: title,
            detail: "\(author)",
            notice: "Bundled edition.",
            license: .libraryPublicDomain
        )
    }

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
        SettingsDetailScaffold(title: license.title, intro: "Read the terms and notices for this work.") {
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
