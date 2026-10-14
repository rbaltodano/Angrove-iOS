import Observation
import SwiftUI

/// Requests and presentation flags use the same contract as CurrentConversationView.
@MainActor @Observable final class MacTreeControls {
    var selectionRequest = 0
    var clearSelectionRequest = 0
    var dismissHoverRequest = 0
    var createConceptRequest = 0
    var studyRequest = 0
    var studyExitRequest = 0
    var studyToolsRequest = 0
    var studyBranchConfirmRequest = 0
    var midpointEnterRequest = 0
    var midpointCenterRequest = 0
    var midpointPlaceRequest = 0
    var inquireConnectionRequest = 0
    var searchPreviousRequest = 0
    var searchNextRequest = 0
    var searchQuery = ""
    var searchActive = false
    var searchIndex = 0
    var searchCount = 0
    var hasHover = false
    var hasInsightHover = false
    var selectedCount = 0
    var isStudy = false
    var studyToolsOpen = false
    var studyBranchCount = 2
    var isMidpoint = false
    var isGenerating = false
    var hoveredConcept: ConceptDefinition?
}
