//
//  LiquidCoderApp.swift
//  LiquidCoder
//
//  Created by Reom Nagasaka on 2026/04/30.
//

import SwiftUI

@main
struct LiquidCoderApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var runtime = CodexRuntime()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(runtime)
        }
        .commands {
            LiquidCoderCommands()
        }
    }
}

private struct LiquidCoderCommands: Commands {
    @FocusedValue(\.sendPromptAction) private var sendPromptAction
    @FocusedValue(\.newChatAction) private var newChatAction
    @FocusedValue(\.newProjectAction) private var newProjectAction

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Chat") {
                newChatAction?()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(newChatAction == nil)

            Button("New Project") {
                newProjectAction?()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(newProjectAction == nil)
        }

        CommandMenu("Session") {
            Button("Send Prompt") {
                sendPromptAction?()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(sendPromptAction == nil)
        }
    }
}
