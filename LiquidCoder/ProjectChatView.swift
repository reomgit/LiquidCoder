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
    @ObservedObject var runtime: CodexRuntime
    @Binding var draftPrompt: String
    let sendPrompt: () -> Void

    private var latestSession: CodexSession? {
        project.sessions.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if let latestSession {
                SessionContent(project: project, session: latestSession)
            } else {
                NewSessionContent(project: project)
            }

            PromptComposer(
                project: project,
                isSessionActive: runtime.hasActiveSession(for: project.id),
                draftPrompt: $draftPrompt,
                sendPrompt: sendPrompt
            )
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
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

private struct NewSessionContent: View {
    let project: CodexProject

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("What should Codex do in \(project.name)?")
                .font(.largeTitle.weight(.semibold))
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

                if session.status == .running || session.status == .launching {
                    ProgressView("Codex is running in \(project.name)")
                        .font(.callout)
                }

                ForEach(session.messages) { message in
                    ChatBubble(message: message)
                }
            }
            .padding(32)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
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
        case .created:
            return .secondary
        case .launching, .running:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .secondary
        }
    }
}

private struct PromptComposer: View {
    let project: CodexProject
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
                    Text("Ask Codex anything. @ to mention files or context")
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
                Label("Work locally", systemImage: "laptopcomputer")
                Label(project.branch, systemImage: "arrow.triangle.branch")

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
