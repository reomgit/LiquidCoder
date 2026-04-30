//
//  ContentView.swift
//  LiquidCoder
//
//  Created by Reom Nagasaka on 2026/04/30.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @State private var projects = ProjectStore.load()
    @State private var selectedSessionID: CodexSession.ID?
    @State private var expandedProjectIDs: Set<CodexProject.ID> = []
    @State private var draftPrompt = ""
    @StateObject private var runtime = CodexRuntime()
    @StateObject private var terminalStore = SessionTerminalStore()

    private var selectedSessionLocation: (projectIndex: Int, sessionIndex: Int)? {
        guard let selectedSessionID else {
            return nil
        }

        for (projectIndex, project) in projects.enumerated() {
            if let sessionIndex = project.sessions.firstIndex(where: { $0.id == selectedSessionID }) {
                return (projectIndex, sessionIndex)
            }
        }

        return nil
    }

    var body: some View {
        NavigationSplitView {
            SideView(
                projects: projects,
                selectedSessionID: $selectedSessionID,
                expandedProjectIDs: $expandedProjectIDs,
                addProject: addProject,
                toggleProjectExpansion: toggleProjectExpansion,
                selectSession: selectSession,
                createSession: createSession
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            if let selectedSessionLocation {
                let projectBinding = $projects[selectedSessionLocation.projectIndex]
                let sessionBinding = $projects[selectedSessionLocation.projectIndex].sessions[selectedSessionLocation.sessionIndex]
                let session = projects[selectedSessionLocation.projectIndex].sessions[selectedSessionLocation.sessionIndex]
                let project = projects[selectedSessionLocation.projectIndex]

                ProjectChatView(
                    project: projectBinding,
                    session: sessionBinding,
                    workspace: project.workspace(id: session.workspaceID),
                    runtime: runtime,
                    terminalStore: terminalStore,
                    draftPrompt: $draftPrompt,
                    sendPrompt: sendPrompt
                )
            } else if projects.isEmpty {
                EmptyProjectView(addProject: addProject)
            } else {
                EmptySessionView()
            }
        }
        .frame(minWidth: 880, minHeight: 700)
        .onAppear {
            syncSidebarState(with: projects)
        }
        .onChange(of: projects) { _, newValue in
            ProjectStore.save(newValue)
            syncSidebarState(with: newValue)
        }
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Project"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        guard !projects.contains(where: { $0.rootPath == url.path }) else {
            if let existingProject = projects.first(where: { $0.rootPath == url.path }) {
                expandedProjectIDs.insert(existingProject.id)
                if let firstSession = existingProject.sessions.first {
                    selectedSessionID = firstSession.id
                }
            }
            return
        }

        let bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let project = CodexProject(
            name: url.lastPathComponent,
            rootPath: url.path,
            bookmarkData: bookmarkData
        )
        projects.append(project)
        expandedProjectIDs.insert(project.id)
    }

    private func sendPrompt() {
        sendPrompt(text: draftPrompt)
    }

    private func sendPrompt(text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, let selectedSessionLocation else {
            return
        }

        let projectIndex = selectedSessionLocation.projectIndex
        let sessionIndex = selectedSessionLocation.sessionIndex
        let sessionID = projects[projectIndex].sessions[sessionIndex].id

        guard !runtime.hasActiveSession(for: sessionID) else {
            return
        }

        if projects[projectIndex].sessions[sessionIndex].isUntitled {
            projects[projectIndex].sessions[sessionIndex].title = String(prompt.prefix(54))
        }

        projects[projectIndex].sessions[sessionIndex].messages.append(ChatMessage(role: .user, text: prompt))
        projects[projectIndex].sessions[sessionIndex].status = .launching
        projects[projectIndex].sessions[sessionIndex].failureSummary = nil
        draftPrompt = ""

        let session = projects[projectIndex].sessions[sessionIndex]
        let project = projects[projectIndex]

        do {
            let context = try runtime.prepareWorkspace(for: session, in: project)
            projects[projectIndex].branch = context.sourceBranch
            projects[projectIndex].upsertWorkspace(context.workspace)
            projects[projectIndex].sessions[sessionIndex].workspaceID = context.workspace.id

            let latestSession = projects[projectIndex].sessions[sessionIndex]
            if latestSession.threadID?.isEmpty == false {
                runtime.resumeSession(session: latestSession, context: context, prompt: prompt) { event in
                    apply(event, sessionID: latestSession.id, projectID: context.projectID)
                }
            } else {
                runtime.startSession(session: latestSession, context: context, prompt: prompt) { event in
                    apply(event, sessionID: latestSession.id, projectID: context.projectID)
                }
            }
        } catch {
            let summary = error.localizedDescription
            projects[projectIndex].sessions[sessionIndex].status = .failed
            projects[projectIndex].sessions[sessionIndex].failureSummary = summary
            projects[projectIndex].sessions[sessionIndex].messages.append(ChatMessage(role: .system, text: summary))
            appendTerminalEvent(
                TerminalEvent(
                    sessionID: sessionID,
                    stream: .system,
                    text: summary,
                    parsedEventType: "session.failed"
                ),
                toProjectID: project.id
            )
        }
    }

    private func apply(
        _ event: CodexRuntime.SessionEvent,
        sessionID: CodexSession.ID,
        projectID: CodexProject.ID
    ) {
        guard
            let projectIndex = projects.firstIndex(where: { $0.id == projectID }),
            let sessionIndex = projects[projectIndex].sessions.firstIndex(where: { $0.id == sessionID })
        else {
            return
        }

        switch event {
        case .status(let status):
            projects[projectIndex].sessions[sessionIndex].status = status
            if status != .failed {
                projects[projectIndex].sessions[sessionIndex].failureSummary = nil
            }
        case .threadStarted(let threadID):
            projects[projectIndex].sessions[sessionIndex].threadID = threadID
        case .agentMessage(let text):
            projects[projectIndex].sessions[sessionIndex].messages.append(ChatMessage(role: .codex, text: text))
        case .commandStarted(let text):
            projects[projectIndex].sessions[sessionIndex].lastCommand = text
        case .terminalEvent(let event):
            appendTerminalEvent(event, toProjectID: projectID)
        case .failed(let summary):
            projects[projectIndex].sessions[sessionIndex].status = .failed
            projects[projectIndex].sessions[sessionIndex].failureSummary = summary
            projects[projectIndex].sessions[sessionIndex].messages.append(ChatMessage(role: .system, text: summary))
            appendTerminalEvent(
                TerminalEvent(
                    sessionID: sessionID,
                    stream: .stderr,
                    text: summary,
                    parsedEventType: "session.failed"
                ),
                toProjectID: projectID
            )
        }
    }

    private func appendTerminalEvent(_ event: TerminalEvent, toProjectID projectID: CodexProject.ID) {
        guard
            let projectIndex = projects.firstIndex(where: { $0.id == projectID }),
            let sessionIndex = projects[projectIndex].sessions.firstIndex(where: { $0.id == event.sessionID })
        else {
            return
        }

        projects[projectIndex].sessions[sessionIndex].terminalEvents.append(event)
        if projects[projectIndex].sessions[sessionIndex].terminalEvents.count > 400 {
            let overflow = projects[projectIndex].sessions[sessionIndex].terminalEvents.count - 400
            projects[projectIndex].sessions[sessionIndex].terminalEvents.removeFirst(overflow)
        }
    }

    private func toggleProjectExpansion(_ projectID: CodexProject.ID) {
        if expandedProjectIDs.contains(projectID) {
            expandedProjectIDs.remove(projectID)
        } else {
            expandedProjectIDs.insert(projectID)
        }
    }

    private func selectSession(projectID: CodexProject.ID, sessionID: CodexSession.ID) {
        expandedProjectIDs.insert(projectID)
        selectedSessionID = sessionID
    }

    private func createSession(projectID: CodexProject.ID) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return
        }

        let session = CodexSession()
        projects[projectIndex].sessions.insert(session, at: 0)
        expandedProjectIDs.insert(projectID)
        selectedSessionID = session.id
        draftPrompt = ""
    }

    private func syncSidebarState(with projects: [CodexProject]) {
        let availableProjectIDs = Set(projects.map(\.id))
        expandedProjectIDs = expandedProjectIDs.intersection(availableProjectIDs)

        if expandedProjectIDs.isEmpty, let firstProject = projects.first {
            expandedProjectIDs.insert(firstProject.id)
        }

        if
            let selectedSessionID,
            projects.contains(where: { project in project.sessions.contains(where: { $0.id == selectedSessionID }) })
        {
            return
        }

        if let firstExistingSession = projects.lazy.flatMap(\.sessions).first {
            selectedSessionID = firstExistingSession.id
            if let parentProject = projects.first(where: { project in project.sessions.contains(where: { $0.id == firstExistingSession.id }) }) {
                expandedProjectIDs.insert(parentProject.id)
            }
        } else {
            selectedSessionID = nil
        }
    }
}

#Preview {
    ContentView()
}
