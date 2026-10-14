import SwiftUI

protocol SettingsChoice: CaseIterable, Hashable, Identifiable {
    var title: LocalizedStringResource { get }
}

extension SettingsChoice {
    var id: Self { self }
}

enum SettingsStorageKey {
    static let colorScheme = "aquinas.settings.colorScheme"
    static let conversationBackground = "aquinas.settings.conversationBackground"
    static let insightTreeBackground = "aquinas.settings.insightTreeBackground"
    static let customInstructions = "aquinas.settings.customInstructions"
    static let hapticFeedback = "aquinas.settings.hapticFeedback"
    static let defaultStartScreen = "aquinas.settings.defaultStartScreen"
    static let dailyQuestionNotifications = "aquinas.settings.dailyQuestionNotifications"
    static let completedResponseNotifications = "aquinas.settings.completedResponseNotifications"
    static let dailyQuestionReminderTime = "aquinas.settings.dailyQuestionReminderTime"
    static let conversationMemory = "aquinas.settings.conversationMemory"
    static let appLock = "aquinas.settings.appLock"
    static let appLockGracePeriod = "aquinas.settings.appLockGracePeriod"
    static let conversationalInitiative = "aquinas.settings.conversationalInitiative"
    static let knowledgeLevel = "aquinas.settings.knowledgeLevel"
    static let intellectualChallenge = "aquinas.settings.intellectualChallenge"
    static let theologicalFraming = "aquinas.settings.theologicalFraming"
    static let responseFormat = "aquinas.settings.responseFormat"
    static let citationPreference = "aquinas.settings.citationPreference"
    static let citationFormat = "aquinas.settings.citationFormat"
    static let linkHandling = "aquinas.settings.linkHandling"
    static let conversationTitles = "aquinas.settings.conversationTitles"
    static let insightMapping = "aquinas.settings.insightMapping"
    static let definitionHighlights = "aquinas.settings.definitionHighlights"
    static let dailyQuestionFocus = "aquinas.settings.dailyQuestionFocus"
    static let autoReadResponses = "aquinas.settings.autoReadResponses"
    static let playAudioInBackground = "aquinas.settings.playAudioInBackground"
    static let readAnswersElsewhere = "aquinas.settings.readAnswersElsewhere"
    static let showReaderInControls = "aquinas.settings.showReaderInControls"
    /// Retains the original question-alignment key so existing preferences migrate seamlessly
    /// when question and response alignment become one conversation-wide setting.
    static let conversationTextAlignment = "aquinas.settings.inputTextAlignment"
    static let legacyResponseTextAlignment = "aquinas.settings.responseTextAlignment"

    static let allResettableKeys = [
        colorScheme,
        conversationBackground,
        insightTreeBackground,
        customInstructions,
        hapticFeedback,
        defaultStartScreen,
        dailyQuestionNotifications,
        completedResponseNotifications,
        dailyQuestionReminderTime,
        conversationMemory,
        appLock,
        appLockGracePeriod,
        conversationalInitiative,
        knowledgeLevel,
        intellectualChallenge,
        theologicalFraming,
        responseFormat,
        citationPreference,
        citationFormat,
        linkHandling,
        conversationTitles,
        insightMapping,
        definitionHighlights,
        dailyQuestionFocus,
        autoReadResponses,
        playAudioInBackground,
        readAnswersElsewhere,
        showReaderInControls,
        "aquinas.settings.userName",
        "aquinas.settings.conversationFontSize",
        conversationTextAlignment,
        "aquinas.settings.inputFont",
        legacyResponseTextAlignment,
        "aquinas.settings.responseFont",
        "aquinas.settings.conversationPersonality"
    ]
}
