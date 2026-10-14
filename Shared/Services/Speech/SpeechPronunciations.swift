//
//  SpeechPronunciations.swift
//  Angrove-iOS
//

import Foundation

/// Pronunciations for words misaki's English lexicon does not know, in misaki's phoneme spelling
/// (A = eɪ, I = aɪ, O = oʊ, W = aʊ, Y = ɔɪ, ᵊ = reduced vowel). The curated list covers names and
/// Latin that recur in Angrove responses; anything else gets a rough letter-to-sound guess so the
/// word is still spoken rather than silently dropped.
nonisolated enum SpeechPronunciations {
    static let curated: [String: String] = [
        // Aquinas and his works
        "aquinas": "əkwˈInəs",
        "summa": "sˈumə",
        "theologica": "θˌiəlˈɑʤɪkə",
        "theologiae": "θˌiəlˈOʤiˌA",
        "contra": "kˈɑntɹə",
        "gentiles": "ʤˈɛntˌIlz",
        "sententiarum": "sˌɛntˌɛnʧiˈɑɹəm",
        "libros": "lˈibɹOs",
        "thomistic": "tOmˈɪstɪk",
        "thomism": "tˈOmˌɪzəm",
        "thomist": "tˈOmɪst",
        // Recurring names
        "paul": "pˈɔl",
        "matthew": "mˈæθju",
        "alighieri": "ˌæləɡjˈɛɹi",
        "dionysius": "dˌIənˈɪsiəs",
        "pseudo": "sˈudO",
        "boethius": "bOˈiθiəs",
        "chrysostom": "kɹˈɪsəstəm",
        "damascene": "dˈæməsˌin",
        "averroes": "əvˈɛɹOˌiz",
        "avicenna": "ˌævəsˈɛnə",
        "maimonides": "mImˈɑnədˌiz",
        "origen": "ˈɔɹəʤən",
        "nicomachean": "nˌIkəməkˈiən",
        "peloponnesian": "pˌɛləpənˈiʒən",
        "constantinopolitan": "kˌɑnstæntˌɪnəpˈɑlətᵊn",
        "aristotelianism": "ˌɛɹəstətˈiliənˌɪzəm",
        // Latin and technical vocabulary
        "priori": "pɹIˈɔɹI",
        "posteriori": "pɑstˌɪɹiˈɔɹI",
        "se": "sˈA",
        "sed": "sˈɛd",
        "respondeo": "ɹɛspˈɑndiˌO",
        "actus": "ˈæktəs",
        "purus": "pˈʊɹəs",
        "ligare": "lɪɡˈɑɹA",
        "homoousios": "hˌOmOˈusiˌOs",
        "concupiscible": "kənkjˈupəsəbᵊl",
        "appetible": "ˈæpətəbᵊl",
        "inordinateness": "ɪnˈɔɹdᵊnətnəs",
        "fomes": "fˈOmiz",
        "haecceity": "hɛksˈiəTi",
        "habitus": "hˈæbɪtəs",
        "dei": "dˈAi",
        "deo": "dˈAO",
        "viz": "nˈAmli",
    ]

    /// Phonemes for a word missing from misaki's lexicon, or `nil` to skip it.
    static func phonemes(for rawWord: String) -> String? {
        var word = rawWord.replacingOccurrences(of: "’", with: "'").lowercased()
        var possessive = false
        if word.hasSuffix("'s") {
            word.removeLast(2)
            possessive = true
        }
        word = word.trimmingCharacters(in: CharacterSet.letters.inverted)
        guard !word.isEmpty, word.allSatisfy(\.isLetter) else { return nil }

        guard let base = curated[word] ?? letterToSound(word) else { return nil }
        guard possessive else { return base }
        let last = base.last.map(String.init) ?? ""
        return base + ("szʃʒʧʤ".contains(last) ? "ᵻz" : ("ptkfθ".contains(last) ? "s" : "z"))
    }

    /// A deliberately simple grapheme-to-phoneme guess with stress on the first vowel. It leans
    /// toward Latin and Greek spellings, which are most of what reaches it.
    static func letterToSound(_ word: String) -> String? {
        let rules: [(String, String)] = [
            ("tion", "ʃən"), ("sion", "ʒən"), ("ous", "əs"), ("ius", "iəs"), ("ae", "i"), ("oe", "i"),
            ("ph", "f"), ("th", "θ"), ("ch", "k"), ("sh", "ʃ"), ("qu", "kw"), ("ck", "k"), ("ng", "ŋ"),
            ("gh", "ɡ"), ("ee", "i"), ("oo", "u"), ("ou", "u"), ("ai", "A"), ("ei", "A"), ("au", "ɔ"),
            ("ia", "iə"), ("io", "iO"),
        ]
        let letters = Array(word)
        var output = ""
        var index = 0
        var stressed = false
        func emit(_ phonemes: String) {
            for character in phonemes {
                if !stressed, "AIOWYaeiouæɑɔəɛɪʊʌ".contains(character) {
                    output.append("ˈ")
                    stressed = true
                }
                output.append(character)
            }
        }
        while index < letters.count {
            let rest = String(letters[index...])
            if let (spelling, sound) = rules.first(where: { rest.hasPrefix($0.0) }) {
                emit(sound)
                index += spelling.count
                continue
            }
            let letter = letters[index]
            let next = index + 1 < letters.count ? letters[index + 1] : nil
            if let next, next == letter, !"aeiou".contains(letter) {
                index += 1
                continue
            }
            switch letter {
            case "a": emit("æ")
            case "e": emit(index == letters.count - 1 && letters.count > 3 ? "" : "ɛ")
            case "i": emit("ɪ")
            case "o": emit("ɑ")
            case "u": emit("ʌ")
            case "y": emit(index == 0 ? "j" : "i")
            case "c": emit(next.map { "eiy".contains($0) } == true ? "s" : "k")
            case "g": emit(next.map { "eiy".contains($0) } == true ? "ʤ" : "ɡ")
            case "j": emit("ʤ")
            case "r": emit("ɹ")
            case "x": emit("ks")
            case "q": emit("k")
            case "b", "d", "f", "h", "k", "l", "m", "n", "p", "s", "t", "v", "w", "z": emit(String(letter))
            default: break
            }
            index += 1
        }
        return output.isEmpty ? nil : output
    }
}
