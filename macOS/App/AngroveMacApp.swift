import CoreText
import AppKit
import Darwin
import SwiftUI

@main
struct AngroveMacApp: App {
    private static let isHostingUnitTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }()

    init() {
        MacLaunchOwnership.claim()
        // Register the same bundled typefaces used by iOS, once for this process.
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        Window(MacDesignPreview.isEnabled ? "Angrove – Design Preview" : "Angrove", id: "workspace") {
            if Self.isHostingUnitTests {
                // Match the iPhone test host: unit tests must not open personal stores.
                Color.clear
            } else {
                MacWorkspaceView(support: .current)
                    .ignoresSafeArea(.container, edges: .top)
                    .background(MacWindowChrome())
                    .preferredColorScheme(MacDesignPreview.colorScheme)
            }
        }
        .defaultSize(width: MacDesignPreview.compact ? 760 : 1_440, height: MacDesignPreview.compact ? 540 : 900)
        .windowStyle(.hiddenTitleBar)
        .commands { MacWorkspaceCommands() }
        .restorationBehavior(MacDesignPreview.isEnabled || MacDesignPreview.compact ? .disabled : .automatic)

        Settings {
            if Self.isHostingUnitTests {
                Color.clear
            } else {
                MacSettingsView()
                    .background(MacWindowChrome())
            }
        }
    }
}

/// Holds ownership until process exit, before any personal stores or runtime are opened.
@MainActor private enum MacLaunchOwnership {
    private static var descriptor: Int32 = -1

    static func claim() {
        // Isolated design fixtures and app-hosted tests don't own the live workspace.
        guard !MacDesignPreview.isEnabled,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              ProcessInfo.processInfo.environment["XCTestBundlePath"] == nil,
              NSClassFromString("XCTestCase") == nil else { return }
        do {
            let directory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true).appending(path: "Angrove-macOS")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            descriptor = open(directory.appending(path: "workspace.lock").path,
                              O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                let code = errno
                close(descriptor)
                descriptor = -1
                guard code == EWOULDBLOCK else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
                if let identifier = Bundle.main.bundleIdentifier {
                    NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                        .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
                        .activate(options: [.activateAllWindows])
                }
                exit(EXIT_SUCCESS)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Angrove couldn't open its workspace"
            alert.informativeText = "The app couldn't verify that this is the only running workspace. Quit Angrove and try again.\n\n\(error.localizedDescription)"
            alert.runModal()
            exit(EXIT_FAILURE)
        }
    }
}
