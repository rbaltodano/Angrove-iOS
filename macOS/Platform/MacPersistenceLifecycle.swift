import AppKit

/// Normal Quit waits for protected writes after views publish their final editor/viewport state.
@MainActor final class MacPersistenceLifecycle: NSObject, NSApplicationDelegate {
    private var isFinishing = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isFinishing else { return .terminateLater }
        isFinishing = true
        MacApplicationRuntime.shared.modelTasks.cancelTasks { _ in true }
        ResponseSpeechPlayer.shared.stop()
        NotificationCenter.default.post(name: .macWillFlushPersistence, object: nil)
        Task {
            await InquiryPersistenceStore.flushAsync()
            await SerializedPersonalStore.shared.flush()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

extension Notification.Name {
    static let macWillFlushPersistence = Notification.Name("angrove.mac.persistence.will-flush")
}
