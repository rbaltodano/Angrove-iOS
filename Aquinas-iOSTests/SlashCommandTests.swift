import Testing
@testable import Aquinas_iOS

@Suite("Slash commands")
struct SlashCommandTests {
    @Test("Rename accepts a prompt or a name while preserving the name's case")
    func renameInvocation() {
        #expect(SlashCommand.invocation(for: " /rename ") == .rename(nil))
        #expect(SlashCommand.invocation(for: "/ReNaMe  My Reading Notes  ") == .rename("My Reading Notes"))
        #expect(SlashCommand.invocation(for: "/renameNext") == nil)
    }

    @Test("Commands without arguments keep their existing behavior")
    func existingInvocations() {
        #expect(SlashCommand.invocation(for: "/compact") == .compact)
        #expect(SlashCommand.invocation(for: " /clear ") == .clear)
        #expect(SlashCommand.invocation(for: "/clear extra") == nil)
    }
}
