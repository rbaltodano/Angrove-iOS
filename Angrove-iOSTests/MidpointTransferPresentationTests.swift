import SwiftUI
import Testing
@testable import Angrove_iOS

struct MidpointTransferPresentationTests {
    @Test("A new connection attaches before its old connection releases or its Insight moves")
    func preservesAttachmentThroughoutTransfer() {
        for step in 0...200 {
            let phase = MidpointTransferPresentation(progress: CGFloat(step) / 200)
            if phase.connectorGrowth < 1 {
                #expect(phase.oldConnectorOpacity == 1)
                #expect(phase.pullProgress == 0)
            }
            if phase.oldConnectorOpacity > 0 {
                #expect(phase.pullProgress == 0)
            }
            if phase.pullProgress > 0 {
                #expect(phase.connectorGrowth == 1)
                #expect(phase.oldConnectorOpacity == 0)
            }
        }
    }

    @Test("Connectors settle without leaving a second parent connection")
    func settlesConnectors() {
        var previous = MidpointTransferPresentation(progress: 0)
        for step in 1...200 {
            let next = MidpointTransferPresentation(progress: CGFloat(step) / 200)
            #expect(next.connectorGrowth >= previous.connectorGrowth)
            #expect(next.oldConnectorOpacity <= previous.oldConnectorOpacity)
            previous = next
        }
        #expect(previous.connectorGrowth == 1)
        #expect(previous.oldConnectorOpacity == 0)
        #expect(previous.pullProgress == 1)
    }

    @Test("Insights use the exact drag-release spring, including its rubberband overshoot")
    func matchesDragReleaseSpring() {
        for elapsed in [0.05, 0.15, 0.3, 0.5] {
            let phase = MidpointTransferPresentation(progress:
                CGFloat((MidpointTransferPresentation.pullStart + elapsed) / MidpointTransferPresentation.duration))
            #expect(abs(Double(phase.pullProgress) - Spring.relaxed.value(target: 1.0, time: elapsed)) < 0.000001)
        }
        let overshoot = (1...200).map {
            MidpointTransferPresentation(progress: CGFloat($0) / 200).pullProgress
        }.max()!
        #expect(overshoot > 1)
    }

}
