//
//  SuggestedInsightSheet.swift
//  Angrove-iOS
//

import SwiftUI

// MARK: - Suggested Insight Sheet

struct SuggestedInsightSheet: View {
    let node: NodeModel
    var onDismissSuggestedNode: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        ConversationHeading(title: node.conceptLabel) { label in
                            Text(label)
                                .font(.figtreeDisplay)
                                .lineSpacing(8)
                                .foregroundColor(AngroveTheme.Colors.primaryReadable)
                        }

                        Text("Suggested connection")
                            .paragraphFont()
                            .foregroundColor(AngroveTheme.Colors.paragraphText)
                    }

                    Spacer()

                    Button(action: onDismissSuggestedNode) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .angroveIconControl()
                    }
                    .buttonStyle(.plain)
                }

                ForEach(node.suggestedInsights ?? node.insights) { insight in
                    InsightTreeInsightCard(
                        insight: insight,
                        showsStartConversation: true,
                        onStartConversation: {}
                    )
                }
            }
            .padding(24)
        }
        .background(AngroveTheme.Colors.canvas)
    }
}
