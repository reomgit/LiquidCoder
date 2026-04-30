//
//  AppState.swift
//  LiquidCoder
//
//  Created by OpenAI Codex on 2026/04/30.
//

import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    enum AddProjectResult {
        case added(projectID: CodexProject.ID)
        case existing(projectID: CodexProject.ID, firstSessionID: CodexSession.ID?)
    }

    @Published var projects: [CodexProject] {
        didSet {
            ProjectStore.save(projects)
        }
    }

    init(projects: [CodexProject]) {
        self.projects = projects
    }

    convenience init() {
        self.init(projects: ProjectStore.load())
    }

    func location(for sessionID: CodexSession.ID?) -> (projectIndex: Int, sessionIndex: Int)? {
        guard let sessionID else {
            return nil
        }

        for (projectIndex, project) in projects.enumerated() {
            if let sessionIndex = project.sessions.firstIndex(where: { $0.id == sessionID }) {
                return (projectIndex, sessionIndex)
            }
        }

        return nil
    }

    func containsSession(_ sessionID: CodexSession.ID?) -> Bool {
        guard let sessionID else {
            return false
        }

        return projects.contains { project in
            project.sessions.contains { $0.id == sessionID }
        }
    }

    func firstSessionReference() -> (projectID: CodexProject.ID, sessionID: CodexSession.ID)? {
        for project in projects {
            if let session = project.sessions.first {
                return (project.id, session.id)
            }
        }

        return nil
    }

    func parentProjectID(for sessionID: CodexSession.ID) -> CodexProject.ID? {
        projects.first { project in
            project.sessions.contains { $0.id == sessionID }
        }?.id
    }

    func addProject(at url: URL) -> AddProjectResult {
        if let existingProject = projects.first(where: { $0.rootPath == url.path }) {
            return .existing(
                projectID: existingProject.id,
                firstSessionID: existingProject.sessions.first?.id
            )
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
        return .added(projectID: project.id)
    }

    func createSession(projectID: CodexProject.ID) -> CodexSession.ID? {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return nil
        }

        let session = CodexSession()
        projects[projectIndex].sessions.insert(session, at: 0)
        return session.id
    }

    func setProjectWorkspaceMode(_ mode: ProjectWorkspaceMode, for projectID: CodexProject.ID) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return
        }

        projects[projectIndex].workspaceMode = mode
    }

    func markSessionStarting(sessionID: CodexSession.ID, prompt: String) -> (project: CodexProject, session: CodexSession)? {
        guard let location = location(for: sessionID) else {
            return nil
        }

        if projects[location.projectIndex].sessions[location.sessionIndex].isUntitled {
            projects[location.projectIndex].sessions[location.sessionIndex].title = String(prompt.prefix(54))
        }

        projects[location.projectIndex].sessions[location.sessionIndex].messages.append(
            ChatMessage(role: .user, text: prompt)
        )
        projects[location.projectIndex].sessions[location.sessionIndex].status = .launching
        projects[location.projectIndex].sessions[location.sessionIndex].failureSummary = nil

        return (
            project: projects[location.projectIndex],
            session: projects[location.projectIndex].sessions[location.sessionIndex]
        )
    }

    func applyPreparedWorkspace(
        _ context: CodexRuntime.PreparedSessionContext,
        to sessionID: CodexSession.ID
    ) -> CodexSession? {
        guard let location = location(for: sessionID) else {
            return nil
        }

        projects[location.projectIndex].branch = context.sourceBranch
        projects[location.projectIndex].upsertWorkspace(context.workspace)
        projects[location.projectIndex].sessions[location.sessionIndex].workspaceID = context.workspace.id
        return projects[location.projectIndex].sessions[location.sessionIndex]
    }

    func failSession(_ sessionID: CodexSession.ID, summary: String, stream: TerminalEventStream = .system) {
        guard let location = location(for: sessionID) else {
            return
        }

        projects[location.projectIndex].sessions[location.sessionIndex].status = .failed
        projects[location.projectIndex].sessions[location.sessionIndex].failureSummary = summary
        projects[location.projectIndex].sessions[location.sessionIndex].messages.append(
            ChatMessage(role: .system, text: summary)
        )
        appendTerminalEvent(
            TerminalEvent(
                sessionID: sessionID,
                stream: stream,
                text: summary,
                parsedEventType: "session.failed"
            ),
            toProjectID: projects[location.projectIndex].id
        )
    }

    func apply(
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
            failSession(sessionID, summary: summary, stream: .stderr)
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
}
