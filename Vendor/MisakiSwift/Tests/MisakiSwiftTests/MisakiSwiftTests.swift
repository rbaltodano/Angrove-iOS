import Testing
@testable import MisakiSwift

@Test func phonemizesCommonEnglish() {
  let g2p = EnglishG2P(british: false)
  #expect(g2p.phonemize(text: "Hello world!").0 == "həlˈO wˈɜɹld!")
}

@Test func readsNumbersInTheTwenties() {
  let g2p = EnglishG2P(british: false)
  #expect(g2p.phonemize(text: "It took place in 325.").0 == "ˌɪt tˈʊk plˈAs ɪn θɹˈi hˈʌndɹəd twˈɛnti fˈIv.")
}

@Test func routesUnknownWordsThroughFallback() {
  var asked: [String] = []
  let g2p = EnglishG2P(british: false, unk: "", fallback: { asked.append($0); return nil })
  _ = g2p.phonemize(text: "Zqxwv is unknown.")
  #expect(asked == ["Zqxwv"])
}
