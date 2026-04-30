//
//  ProjectChatView.swift
//  LiquidCoder
//
//  Created by Reom Nagasaka on 2026/04/30.
//

import AppKit
import SwiftUI

struct ProjectChatView: View {
    @Binding var project: CodexProject
    @Binding var session: CodexSession
    let workspace: CodexWorkspace?
    @ObservedObject var runtime: CodexRuntime
    @ObservedObject var terminalStore: SessionTerminalStore
    @Binding var draftPrompt: String
    let sendPrompt: () -> Void
    let stopSession: () -> Void
    let rerunLastPrompt: () -> Void

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 900 {
                HSplitView {
                    chatColumn
                        .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)

                    terminalColumn
                        .frame(minWidth: 260, idealWidth: 320, maxWidth: 400)
                }
            } else {
                VStack(spacing: 0) {
                    chatColumn

                    Divider()

                    terminalColumn
                        .frame(maxWidth: .infinity)
                        .frame(height: min(320, max(220, geometry.size.height * 0.35)))
                }
            }
        }
        .background(.background)
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    openInFinder(project)
                } label: {
                    Label("Finder", systemImage: "folder")
                }

                Menu {
                    Button("Cursor") { openApp("Cursor", project: project) }
                    Button("VS Code") { openApp("Visual Studio Code", project: project) }
                    Button("Ghostty") { openApp("Ghostty", project: project) }
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }

                Divider()

                Button {
                } label: {
                    Label("Commit", systemImage: "checkmark.seal")
                }

                Button {
                } label: {
                    Label("Commit & Push", systemImage: "arrow.up.right.circle")
                }
                .buttonStyle(.glassProminent)
            }
        }
    }

    private var chatColumn: some View {
        VStack(spacing: 0) {
            if session.messages.isEmpty && session.terminalEvents.isEmpty && session.failureSummary == nil {
                NewSessionContent(project: project)
            } else {
                SessionContent(project: project, session: session)
            }

            PromptComposer(
                project: project,
                workspace: workspace,
                isSessionActive: runtime.hasActiveSession(for: session.id),
                draftPrompt: $draftPrompt,
                sendPrompt: sendPrompt
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private var terminalColumn: some View {
        let terminalController = terminalStore.controller(
            for: session.id,
            project: project,
            workspace: workspace
        )

        return TerminalMonitorSidebar(
            project: project,
            session: session,
            workspace: workspace,
            terminalController: terminalController,
            isSessionActive: runtime.hasActiveSession(for: session.id),
            stopSession: stopSession,
            rerunLastPrompt: rerunLastPrompt
        )
    }
}

struct EmptyProjectView: View {
    let addProject: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Add a project to begin", systemImage: "folder.badge.plus")
        } description: {
            Text("LiquidCoder starts empty. Add a local project folder, then run Codex sessions inside it.")
        } actions: {
            Button("Add Project", action: addProject)
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptySessionView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Select a chat", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Expand a project in the sidebar, open an existing chat, or create a new one.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NewSessionContent: View {
    let project: CodexProject

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("What should Codex do in \(project.name)?")
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("This session is idle. Your first message creates an isolated workspace, launches Codex there, and keeps the thread resumable.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(project.rootPath)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SessionContent: View {
    let project: CodexProject
    let session: CodexSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(session.title)
                            .font(.title.weight(.semibold))

                        SessionStatusBadge(status: session.status)
                    }

                    if let failureSummary = session.failureSummary {
                        Text(failureSummary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if session.status == .launching || session.status == .running {
                        ProgressView("Codex is running in \(project.name)")
                            .font(.callout)
                    }

                    ForEach(session.messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(32)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                scrollToLastMessage(proxy)
            }
            .onChange(of: session.messages.count) { _, _ in
                scrollToLastMessage(proxy)
            }
        }
    }

    private func scrollToLastMessage(_ proxy: ScrollViewProxy) {
        guard let lastID = session.messages.last?.id else {
            return
        }

        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 80)
            }

            Text(message.text)
                .font(.body)
                .textSelection(.enabled)
                .padding(14)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if message.role != .user {
                Spacer(minLength: 80)
            }
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color.accentColor.opacity(0.15)
        case .codex:
            return Color.secondary.opacity(0.10)
        case .system:
            return Color.orange.opacity(0.12)
        }
    }
}

private struct SessionStatusBadge: View {
    let status: CodexSessionStatus

    var body: some View {
        Label(status.label, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.12), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch status {
        case .idle, .cancelled:
            return .secondary
        case .launching, .running:
            return .orange
        case .waitingForInput, .completed:
            return .green
        case .failed:
            return .red
        }
    }
}

private struct PromptComposer: View {
    let project: CodexProject
    let workspace: CodexWorkspace?
    let isSessionActive: Bool
    @Binding var draftPrompt: String
    let sendPrompt: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draftPrompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 72, maxHeight: 110)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                if draftPrompt.isEmpty {
                    Text("Ask Codex anything. The first prompt creates an isolated worktree for this session.")
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(.horizontal, 18)
                        .padding(.top, 17)
                        .allowsHitTesting(false)
                }
            }

            Divider()

            HStack(spacing: 14) {
                Label("Full access", systemImage: "shield.lefthalf.filled")
                    .foregroundStyle(.orange)

                if isSessionActive {
                    Label("Session running", systemImage: "waveform")
                        .foregroundStyle(.orange)
                }

                Spacer()

                Label(project.name, systemImage: "folder")
                if let workspace {
                    Label(workspace.branchName, systemImage: "arrow.triangle.branch")
                } else {
                    Label(project.branch, systemImage: "arrow.triangle.branch")
                }

                Button(action: sendPrompt) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(sendButtonColor, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(promptIsEmpty)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 44)
        }
        .glassEffect(.regular.tint(.white.opacity(0.20)).interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(maxWidth: 760)
    }

    private var promptIsEmpty: Bool {
        draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSessionActive
    }

    private var sendButtonColor: Color {
        promptIsEmpty ? Color.secondary.opacity(0.55) : Color.accentColor
    }
}

private struct TerminalMonitorSidebar: View {
    let project: CodexProject
    let session: CodexSession
    let workspace: CodexWorkspace?
    @ObservedObject var terminalController: SessionTerminalController
    let isSessionActive: Bool
    let stopSession: () -> Void
    let rerunLastPrompt: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Terminal")
                    .font(.headline.weight(.semibold))

                Spacer()

                SessionStatusBadge(status: session.status)
            }

            VStack(alignment: .leading, spacing: 8) {
                DetailRow(label: "Project", value: project.name)
                DetailRow(label: "Root", value: project.rootPath)
                if let workspace {
                    DetailRow(label: "Branch", value: workspace.branchName)
                    DetailRow(label: "Worktree", value: workspace.worktreePath)
                }
                if let threadID = session.threadID {
                    DetailRow(label: "Thread", value: threadID)
                }
                DetailRow(
                    label: terminalController.currentDirectory == nil ? "Shell Root" : "Shell CWD",
                    value: terminalController.currentDirectory ?? terminalController.workingDirectory
                )
            }

            if let lastCommand = session.lastCommand {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last Command")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(lastCommand)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 90)
                    .padding(10)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            HStack(spacing: 10) {
                Button("Stop", action: stopSession)
                    .disabled(!isSessionActive)
                Button("Rerun", action: rerunLastPrompt)
                    .disabled(isSessionActive || session.lastPrompt == nil)
                Button(terminalController.isRunning ? "Shell Active" : "Start Shell") {
                    terminalController.relaunch()
                }
                .disabled(terminalController.isRunning)
            }
            .buttonStyle(.glass)

            HStack {
                Text(terminalController.terminalTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if let lastExitCode = terminalController.lastExitCode {
                    Text("exit \(lastExitCode)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            IntegratedTerminalView(controller: terminalController)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(20)
        .background(.bar)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}

private func openInFinder(_ project: CodexProject) {
    withProjectAccess(project) { url in
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private func openApp(_ appName: String, project: CodexProject) {
    withProjectAccess(project) { url in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appName, url.path]
        try? process.run()
    }
}

private func withProjectAccess(_ project: CodexProject, action: (URL) -> Void) {
    let url = project.resolvedRootURL
    let accessed = url.startAccessingSecurityScopedResource()
    action(url)

    if accessed {
        url.stopAccessingSecurityScopedResource()
    }
}
