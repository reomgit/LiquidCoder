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

    var body: some View {
        GeometryReader { geometry in
            if session.isTerminalVisible {
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
            } else {
                chatColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.background)
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        session.isTerminalVisible.toggle()
                    }
                } label: {
                    Image(systemName: session.isTerminalVisible ? "apple.terminal.fill" : "apple.terminal")
                        .imageScale(.medium)
                        .frame(width: 18, height: 18)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(PressableButtonStyle())
                .help(session.isTerminalVisible ? "Hide Terminal" : "Show Terminal")

                Menu {
                    Button("Finder") { openInFinder(project) }
                    Button("Cursor") { openApp("Cursor", project: project) }
                    Button("VS Code") { openApp("Visual Studio Code", project: project) }
                } label: {
                    Label("Open In", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(PressableButtonStyle())
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
                projectName: project.name,
                projectBranch: project.branch,
                workspaceMode: $project.workspaceMode,
                permissionMode: $project.permissionMode,
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
            terminalController: terminalController
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
            Text(sessionIntro)
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

    private var sessionIntro: String {
        switch project.workspaceMode {
        case .isolated:
            return "This session is idle. Your first message creates a dedicated worktree and branch for this chat, launches Codex there, and keeps the thread resumable."
        case .shared:
            return "This session is idle. Your first message reuses the project root branch and worktree, launches Codex there, and keeps the thread resumable. LiquidCoder blocks concurrent shared runs so chats do not stomp each other."
        }
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
    private static let composerHorizontalInset: CGFloat = 14
    private static let composerVerticalInset: CGFloat = 10

    let projectName: String
    let projectBranch: String
    @Binding var workspaceMode: ProjectWorkspaceMode
    @Binding var permissionMode: CodexPermissionMode
    let workspace: CodexWorkspace?
    let isSessionActive: Bool
    @Binding var draftPrompt: String
    let sendPrompt: () -> Void
    @State private var sendHovered = false

    var body: some View {
        VStack(spacing: 0) {
            TextField(
                "",
                text: $draftPrompt,
                prompt: Text(promptPlaceholder).foregroundStyle(.secondary.opacity(0.6)),
                axis: .vertical
            )
            .font(.body)
            .textFieldStyle(.plain)
            .lineLimit(1...4)
            .padding(.horizontal, Self.composerHorizontalInset)
            .padding(.vertical, Self.composerVerticalInset)
            .frame(minHeight: 72, maxHeight: 110, alignment: .top)

            Divider()

            HStack(spacing: 14) {
                Menu {
                    ForEach(CodexPermissionMode.allCases, id: \.self) { mode in
                        Button {
                            permissionMode = mode
                        } label: {
                            Label(mode.label, systemImage: mode.systemImage)
                        }
                    }
                } label: {
                    Label(permissionMode.label, systemImage: permissionMode.systemImage)
                        .foregroundStyle(permissionTint)
                }
                .buttonStyle(.plain)
                .help(permissionMode.shortDescription)

                if isSessionActive {
                    Label("Session running", systemImage: "waveform")
                        .foregroundStyle(.orange)
                }

                Spacer()

                Label(projectName, systemImage: "folder")
                Button {
                    isSharedMode.wrappedValue.toggle()
                } label: {
                    Label(workspaceMode.label, systemImage: workspaceMode == .shared ? "square.3.layers.3d.down.right" : "square.split.2x2")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Toggle workspace mode. Shared reuses the project root worktree.")
                if let workspace {
                    Label(workspace.branchName, systemImage: "arrow.triangle.branch")
                } else {
                    Label(projectBranch, systemImage: "arrow.triangle.branch")
                }

                Button(action: sendPrompt) {
                    Image(systemName: promptIsEmpty ? "arrow.up" : "arrow.up.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(sendButtonColor, in: Circle())
                        .scaleEffect(sendHovered && !promptIsEmpty ? 1.06 : 1)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PressablePlainButtonStyle(pressedScale: 0.9))
                .disabled(promptIsEmpty)
                .onHover { isHovering in
                    withAnimation(.easeInOut(duration: 0.14)) {
                        sendHovered = isHovering
                    }
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 44)
        }
        .glassEffect(.regular.tint(.white.opacity(0.20)).interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(maxWidth: 760)
        .animation(.easeInOut(duration: 0.16), value: promptIsEmpty)
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isSessionActive)
    }

    private var promptIsEmpty: Bool {
        draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSessionActive
    }

    private var promptPlaceholder: String {
        switch workspaceMode {
        case .isolated:
            return "Ask Codex anything. The first prompt creates a dedicated worktree and branch for this chat."
        case .shared:
            return "Ask Codex anything. The first prompt reuses the project root branch and worktree for this chat."
        }
    }

    private var isSharedMode: Binding<Bool> {
        Binding(
            get: { workspaceMode == .shared },
            set: { workspaceMode = $0 ? .shared : .isolated }
        )
    }

    private var sendButtonColor: Color {
        promptIsEmpty ? Color.secondary.opacity(0.55) : Color.accentColor
    }

    private var permissionTint: Color {
        switch permissionMode {
        case .defaultConfig:
            return .secondary
        case .manualReview:
            return .orange
        case .fullAccess:
            return .red
        }
    }
}

private struct TerminalMonitorSidebar: View {
    @ObservedObject var terminalController: SessionTerminalController

    var body: some View {
        IntegratedTerminalView(controller: terminalController)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
