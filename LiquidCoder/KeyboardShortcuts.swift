import SwiftUI

struct SendPromptActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct NewChatActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct NewProjectActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var sendPromptAction: (() -> Void)? {
        get { self[SendPromptActionKey.self] }
        set { self[SendPromptActionKey.self] = newValue }
    }

    var newChatAction: (() -> Void)? {
        get { self[NewChatActionKey.self] }
        set { self[NewChatActionKey.self] = newValue }
    }

    var newProjectAction: (() -> Void)? {
        get { self[NewProjectActionKey.self] }
        set { self[NewProjectActionKey.self] = newValue }
    }
}
