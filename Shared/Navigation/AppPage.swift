//
//  AppPage.swift
//  Angrove-iOS
//

import Foundation

enum AppPage: Equatable {
    case home
    case library
    case conversation
    case openConversations
    case settings
    case insights
    case studyTopics

    var sidebarIconName: String {
        switch self {
        case .home: "house"
        case .library: "books.vertical"
        case .conversation, .openConversations: "text.word.spacing"
        case .settings: "gearshape"
        case .insights: "brain.head.profile"
        case .studyTopics: "square.stack"
        }
    }

    var returnTitle: String {
        switch self {
        case .home: String(localized: "Home")
        case .library: String(localized: "Library")
        case .conversation: String(localized: "Conversation")
        case .openConversations: String(localized: "Conversations")
        case .settings: String(localized: "Settings")
        case .insights: String(localized: "Insight Tree")
        case .studyTopics: String(localized: "Study Topics")
        }
    }
}
