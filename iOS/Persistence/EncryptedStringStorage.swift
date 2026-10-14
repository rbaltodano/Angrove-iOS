import SwiftUI

/// A view-local value backed by encrypted preferences; bindings enqueue protected writes off the main actor.
@propertyWrapper
struct EncryptedStringStorage: DynamicProperty {
    @State private var value: String
    private let key: String

    init(wrappedValue: String, _ key: String) {
        self.key = key
        _value = State(initialValue: SerializedPersonalStore.shared.string(for: key, defaultValue: wrappedValue))
    }

    var wrappedValue: String {
        get { value }
        nonmutating set {
            SerializedPersonalStore.shared.setString(newValue, for: key)
            value = newValue
        }
    }
    var projectedValue: Binding<String> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}
