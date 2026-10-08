//
//  SpeechTextNormalizer.swift
//  Angrove-iOS
//

import Foundation

/// Turns a response's plain text into spoken sentences: strips leftover markdown and Insight
/// braces, expands abbreviations the lexicon reads badly, and splits on sentence ends and lines.
nonisolated enum SpeechTextNormalizer {
    private static let replacements: [(pattern: String, template: String)] = [
        (#"\[([^\]]+)\]\([^)]*\)"#, "$1"),          // [text](url) -> text
        (#"\{\{|\}\}"#, ""),                         // Insight braces
        (#"[*_`#>]+"#, ""),                          // emphasis, code, headings, quotes
        (#"(?m)^\s*(?:[-•]|\d+[.)])\s+"#, ""),        // list markers
        (#"\bSt\.?\s+(?=\p{Lu})"#, "Saint "),
        (#"\bSS\.\s+(?=\p{Lu})"#, "Saints "),
        (#"\bcf\.\s"#, "compare "),
        (#"\be\.g\.,?\s"#, "for example, "),
        (#"\bi\.e\.,?\s"#, "that is, "),
        (#"\bq\.\s*(?=\d)"#, "question "),
        (#"\ba\.\s*(?=\d)"#, "article "),
        (#"\bobj\.\s*(?=\d)"#, "objection "),
        (#"\bad\s+(?=\d)"#, "reply to objection "),
    ]

    static func sentences(in text: String) -> [String] {
        var text = text
        for (pattern, template) in replacements {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return text
            .components(separatedBy: .newlines)
            .flatMap { line in
                line.replacingOccurrences(of: #"(?<=[.!?…])["”’)]?\s+"#, with: "$0\n", options: .regularExpression)
                    .components(separatedBy: "\n")
            }
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains(where: \.isLetter) || $0.contains(where: \.isNumber) }
    }
}
