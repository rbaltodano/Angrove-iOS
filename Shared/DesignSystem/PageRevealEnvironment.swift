import SwiftUI

extension EnvironmentValues {
    /// Decorative entrances wait until the app's boot mask has finished revealing the page.
    @Entry var isBootRevealComplete = true
    /// Text entrances can run alongside the page's initial slide-up reveal.
    @Entry var isBootPageRevealAnimating = true
}
