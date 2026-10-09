import SwiftUI
import Testing
import UIKit
@testable import Angrove_iOS

@Suite("Library spoken-word movement", .serialized)
@MainActor
struct LibraryWordLiftTests {
    @Test("Reader words ease into their lift and retain completed words' positions")
    func liftTransition() async throws {
        let view = AskingTextView()
        let text = NSAttributedString(string: "One two three", attributes: [.font: UIFont.systemFont(ofSize: 16)])
        view.baseText = text
        view.attributedText = text
        view.prepareSpeechTokens(sourceID: "test", chunkIndex: 0)
        view.applySpeech(.init(readBefore: 0, active: 0), force: false)
        func lift(_ location: Int) -> CGFloat {
            (view.textStorage.attribute(.baselineOffset, at: location, effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0
        }
        if !UIAccessibility.isReduceMotionEnabled {
            #expect(lift(0) < 0.1)
            // Sample frequently rather than at one instant, so frame timing on slower machines
            // cannot skip the in-between positions that show the word eases rather than jumps.
            var sawIntermediateLift = false
            for _ in 0..<40 where !sawIntermediateLift {
                try await Task.sleep(for: .milliseconds(10))
                sawIntermediateLift = lift(0) > 0 && lift(0) < AskingTextView.liftHeight
            }
            #expect(sawIntermediateLift)
        }
        try await Task.sleep(for: .milliseconds(450))
        #expect(abs(lift(0) - AskingTextView.liftHeight) < 0.01)
        view.applySpeech(.init(readBefore: 1, active: 1), force: false)
        #expect(abs(lift(0) - AskingTextView.liftHeight) < 0.01)
        if !UIAccessibility.isReduceMotionEnabled { #expect(lift(4) < 0.1) }
        try await Task.sleep(for: .milliseconds(450))
        #expect(abs(lift(4) - AskingTextView.liftHeight) < 0.01)
        view.applySpeech(.none, force: false)
        try await Task.sleep(for: .milliseconds(450))
        #expect(abs(lift(0)) < 0.01)
        #expect(abs(lift(4)) < 0.01)
    }
}
