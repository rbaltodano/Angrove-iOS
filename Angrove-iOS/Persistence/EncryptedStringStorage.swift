import SwiftUI

/// A view-local value backed by encrypted preferences; bindings persist synchronously on edit.
@propertyWrapper
struct EncryptedStringStorage: DynamicProperty {
    @State private var value: String
    private let key: String

    init(wrappedValue: String, _ key: String) {
        self.key = key
        _value = State(initialValue: PrivatePreferences.standard.string(forKey: key) ?? wrappedValue)
    }

    var wrappedValue: String {
        get { value }
        nonmutating set {
            PrivatePreferences.standard.set(newValue, forKey: key)
            value = newValue
        }
    }
    var projectedValue: Binding<String> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}
