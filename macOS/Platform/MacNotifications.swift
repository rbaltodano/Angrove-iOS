import AppKit
import UserNotifications

/// System notifications on the Mac: answers that finish while you are elsewhere, and the
/// optional daily Question of the Day reminder. Both reuse the iPhone's preference keys.
@MainActor enum MacNotifications {
    private static let conversationKey = "conversationID"
    private static let delegate = MacNotificationDelegate()

    static func install() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    /// Mirrors the iPhone: the question as the title when known, a short plain preview as the body.
    static func postIfNeeded(for task: ModelTaskSnapshot, isViewing: (UUID) -> Bool) {
        guard case .userQuestion(let branchID, let responseIndex) = task.kind, responseIndex >= 0,
              let conversationID = task.conversationID,
              PrivatePreferences.standard.bool(forKey: SettingsStorageKey.completedResponseNotifications),
              !(NSApp.isActive && isViewing(conversationID)) else { return }
        let conversation = CurrentConversationsStore.load()?.conversations.first { $0.id == conversationID }
        let branch = conversation?.branches.first { $0.id == branchID }
        let question = branch.flatMap { branch in
            branch.activeChatBlocks.prefix(min(responseIndex, branch.activeChatBlocks.count)).reversed()
                .compactMap { block -> String? in
                    guard case .user(let text, _, _) = block else { return nil }
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }.first ?? nonEmpty(branch.topQuestionText)
        }
        var preview: String?
        if let branch, branch.activeChatBlocks.indices.contains(responseIndex),
           case .text(let response) = branch.activeChatBlocks[responseIndex], response != questionCanceledResponseText {
            preview = nonEmpty(AngroveSystemNotifications.responsePreview(from: response))
        }
        let content = UNMutableNotificationContent()
        content.title = nonEmpty(conversation?.title ?? "") ?? "Angrove"
        content.body = preview ?? question ?? "Answer ready"
        content.sound = .default
        content.userInfo = [conversationKey: conversationID.uuidString]
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "aquinas.completed-response.\(UUID().uuidString)", content: content, trigger: nil))
    }

    /// Settings › Read answers finished elsewhere: reads an answer that completed off-screen,
    /// unless something is already being read.
    static func readAloudIfFinishedElsewhere(_ task: ModelTaskSnapshot, isViewing: (UUID) -> Bool) {
        guard AudioSettings.readsAnswersElsewhere,
              case .userQuestion(let branchID, let responseIndex) = task.kind, responseIndex >= 0,
              let conversationID = task.conversationID, !isViewing(conversationID),
              ResponseSpeechPlayer.shared.phase == .idle,
              let conversation = CurrentConversationsStore.load()?.conversations.first(where: { $0.id == conversationID }),
              let branch = conversation.branches.first(where: { $0.id == branchID }),
              branch.activeChatBlocks.indices.contains(responseIndex),
              case .text(let response) = branch.activeChatBlocks[responseIndex],
              !response.isEmpty, response != questionCanceledResponseText else { return }
        ResponseSpeechPlayer.shared.toggleStarting(InlineInsightMarkup.plainText(from: response),
            units: SpokenUnit.units(from: ResponseParser.parseSegments(from: response)),
            source: SpeechSource(title: conversation.title, conversationID: conversationID, page: .conversation))
    }

    fileprivate static func open(_ response: UNNotificationResponse) {
        let info = response.notification.request.content.userInfo
        NSApp.activate()
        if let id = (info[conversationKey] as? String).flatMap(UUID.init(uuidString:)) {
            NotificationCenter.default.post(name: .macOpenConversation, object: id)
        } else if response.notification.request.identifier == AngroveSystemNotifications.dailyQuestionIdentifier {
            NotificationCenter.default.post(name: .macOpenHome, object: nil)
        }
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private final class MacNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    // Shown as a banner even while Angrove is frontmost on another page.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MacNotifications.open(response)
    }
}

extension Notification.Name {
    static let macOpenConversation = Notification.Name("angrove.mac.open-conversation")
    /// Opens Home, or starts the `NewConversationRequest` passed as the object.
    static let macOpenHome = Notification.Name("angrove.mac.open-home")
}
