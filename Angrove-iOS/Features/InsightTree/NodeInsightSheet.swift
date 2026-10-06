//
//  NodeInsightSheet.swift
//  Angrove-iOS
//

import SwiftUI

// MARK: - Node Insight Sheet

struct NodeInsightSheet: View {
    let node: NodeModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                ConversationHeading(title: node.conceptLabel) { label in
                    Text(label)
                        .font(.figtreeDisplay)
                        .lineSpacing(8)
                        .foregroundColor(AngroveTheme.Colors.primaryReadable)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(node.insights) { insight in
                    InsightTreeInsightCard(insight: insight)
                }
            }
            .padding(24)
        }
        .background(AngroveTheme.Colors.canvas)
    }
}

struct InsightTreeInsightCard: View {
    let insight: InsightModel
    var showsStartConversation: Bool = false
    var onStartConversation: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AngroveTheme.Colors.darkGreen)
                    .sfSymbolDrawOn()

                Text(insight.title)
                    .font(.custom("Figtree-Bold", size: 18))
                    .foregroundColor(AngroveTheme.Colors.primaryReadable)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }

            TruncatableParagraph(text: insight.definition)

            if showsStartConversation {
                Button(action: { onStartConversation?() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Start Conversation")
                            .font(.figtreeHeading3)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .angroveCapsuleControl()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(AngroveTheme.Colors.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AngroveTheme.Colors.brownBorder, lineWidth: 1)
        )
        .cardGlow(yOffset: 16)
    }
}
