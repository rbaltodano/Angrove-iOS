//
//  Angrove_iOSApp.swift
//  Angrove-iOS
//
//  Created by Ryan on 4/11/26.
//

import SwiftUI

@main
struct Angrove_iOSApp: App {
    /// Resolved on first use rather than at launch, so a `--litert-probe` process never builds
    /// the app's runtime and MiniLM assets alongside the probe's own and skews its memory.
    private var runtime: AngroveApplicationRuntime { .shared }

    /// True when Xcode's test runner launched the app only to host the unit test bundle.
    private static let isHostingUnitTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }()

    var body: some Scene {
        WindowGroup {
            if Self.isHostingUnitTests {
                // Unit tests don't use the interface. Skipping it keeps its animations off the
                // main actor, which many tests share (it starved timing tests on CI simulators).
                Color.clear
            } else {
#if DEBUG
                // Device probes bypass encrypted storage, so Release builds cannot enter them.
                if ProcessInfo.processInfo.arguments.contains("--litert-probe") {
                    LiteRTDeviceProbeView()
                } else if ProcessInfo.processInfo.arguments.contains("--study-branch-preview") {
                    StudyBranchPreviewView()
                } else {
                    EncryptedStorageGate { mainContent }
                }
#else
                EncryptedStorageGate { mainContent }
#endif
            }
        }
    }

    @ViewBuilder private var mainContent: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--model-download-preview") {
            ModelDownloadPreviewView()
        } else {
            liveContent
        }
#else
        liveContent
#endif
    }

    private var liveContent: some View {
        ContentView(modelTasks: runtime.modelTasks)
            .environment(\.angroveModel, runtime.model)
            .environment(\.embeddingProvider, runtime.embeddingProvider)
    }
}
