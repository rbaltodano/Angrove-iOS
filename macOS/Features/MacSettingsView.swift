import SwiftUI

struct MacSettingsView: View {
    var body: some View {
        Form {
            Section("Angrove for Mac") {
                Text("Development preview")
                Text("Apple silicon · 16 GB memory or more · macOS 27 or later")
            }
            Section("Privacy") {
                Text("The Mac edition will run generation and retrieval on your Mac, following Angrove’s existing on-device architecture.")
            }
        }
        .formStyle(.grouped)
        .font(AngroveTheme.Typography.bodyLarge)
        .frame(width: 520, height: 300)
    }
}
