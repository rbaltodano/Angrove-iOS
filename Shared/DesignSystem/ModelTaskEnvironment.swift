import SwiftUI

private let defaultOpenModelTaskPage: (ModelTaskSnapshot) -> Void = { _ in }

extension EnvironmentValues {
    @Entry var openModelTaskPage: (ModelTaskSnapshot) -> Void = defaultOpenModelTaskPage
    /// Brings the reader back to the conversation being read aloud.
    @Entry var openReadingConversation: (UUID) -> Void = { _ in }
    @Entry var modelCompletionNotifications: ModelCompletionNotificationCenter? = nil
}
