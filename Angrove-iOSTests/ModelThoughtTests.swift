import Testing
@testable import Angrove_iOS

struct ModelThoughtTests {
    private let thought = """
    Thinking Process:

    1.  **Analyze the Request:** The user is asking if 391 is prime.
    2.  **Define "Prime":** A prime number has exactly two divisors.
        *   Check 17: 17 × 23
    """

    @Test("Thought lines drop markdown, list markers, and the boilerplate heading")
    func linesAreCleaned() {
        #expect(ModelThought.lines(in: thought) == [
            "Analyze the Request: The user is asking if 391 is prime.",
            "Define \"Prime\": A prime number has exactly two divisors.",
            "Check 17: 17 × 23"
        ])
    }

    @Test("Planning about persona, tone, structure, and constraints is hidden with its sub-points")
    func writingPlanIsHidden() {
        let thought = """
        1.  **Analyze the Request:** Is human nature good or evil?
        2.  **Determine Persona and Tone:** The persona is Angrove, a philosophical study partner.
        3.  **Formulate a Strategy:**
            *   Present the major opposing viewpoints.
            *   Structure the answer to fit the "scholar friend" tone.
        4.  **Drafting Content - Key Positions:**
            *   *Inherent Evil:* Thinkers like **Hobbes** (state of nature is war).
        5.  **Refining the Tone and Style (Angrove):**
            *   Use clear, modern English.
        6.  **Review against Constraints:**
            *   *No Archaic Prose:* Check.

        7.  **Final Polish:** Explain *why* they hold those views.
        """
        #expect(ModelThought.lines(in: thought) == [
            "Analyze the Request: Is human nature good or evil?",
            "Formulate a Strategy:",
            "Present the major opposing viewpoints.",
            "Inherent Evil: Thinkers like Hobbes (state of nature is war)."
        ])
    }

    @Test("Unnumbered meta sections are hidden through the following blank line")
    func unnumberedPlanIsHidden() {
        let thought = """
        This is a debated topic in philosophy.
        Since no corpus passage was provided, I must adopt the persona of Angrove.

        Structure:
        1.  Acknowledge the complexity.
        2.  Present the "good" argument.

        Tone check: Learned, warmly enthusiastic.
        The atonement is a separate question.
        """
        #expect(ModelThought.lines(in: thought) == [
            "This is a debated topic in philosophy.",
            "The atonement is a separate question."
        ])
    }

    @Test("Live line advances only when a line completes")
    func currentLineIsLastCompletedLine() {
        #expect(ModelThought.currentLine(in: thought) == "Define \"Prime\": A prime number has exactly two divisors.")
        #expect(ModelThought.currentLine(in: thought + "\n") == "Check 17: 17 × 23")
        #expect(ModelThought.currentLine(in: "Thinking Process:\n\n1.  **Analyze") == "Analyze")
        #expect(ModelThought.currentLine(in: "") == nil)
    }
}
