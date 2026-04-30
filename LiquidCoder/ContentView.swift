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
    @State private var selectedProjectID: CodexProject.ID?
    @State private var draftPrompt = ""
    @StateObject private var runtime = CodexRuntime()
 
    private var selectedProjectIndex: Int? {
        guard let selectedProjectID else {
            return nil
        }

        return projects.firstIndex { $0.id == selectedProjectID }
    }

    var body: some View {
        NavigationSplitView {
            SideView(
                projects: projects,
                selectedProjectID: $selectedProjectID,
                addProject: addProject
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            if let selectedProjectIndex {
                ProjectChatView(
                    project: $projects[selectedProjectIndex],
                    runtime: runtime,
                    draftPrompt: $draftPrompt,
                    sendPrompt: sendPrompt
                )
            } else {
                EmptyProjectView(addProject: addProject)
            }
        }
        .frame(minWidth: 980, minHeight: 660)
        .onAppear {
            selectedProjectID = selectedProjectID ?? projects.first?.id
        }
        .onChange(of: projects) { _, newValue in
            ProjectStore.save(newValue)
            if selectedProjectID == nil || !newValue.contains(where: { $0.id == selectedProjectID }) {
                selectedProjectID = newValue.first?.id
            }
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
            selectedProjectID = projects.first { $0.rootPath == url.path }?.id
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
        selectedProjectID = project.id
    }

    private func sendPrompt() {
        let prompt = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, let selectedProjectIndex else {
            return
        }

        let project = projects[selectedProjectIndex]
        guard !runtime.hasActiveSession(for: project.id) else {
            return
        }

        let session = CodexSession(
            title: String(prompt.prefix(54)),
            messages: [ChatMessage(role: .user, text: prompt)]
        )

        projects[selectedProjectIndex].sessions.insert(session, at: 0)
        draftPrompt = ""

        runtime.launch(project: project, sessionID: session.id, prompt: prompt) { event in
            apply(event, sessionID: session.id, projectID: project.id)
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
            projects[projectIndex].sessions[sessionIndex].messages.append(
                ChatMessage(role: .codex, text: text)
            )
        case .failed(let summary):
            projects[projectIndex].sessions[sessionIndex].status = .failed
            projects[projectIndex].sessions[sessionIndex].failureSummary = summary
            projects[projectIndex].sessions[sessionIndex].messages.append(
                ChatMessage(role: .system, text: summary)
            )
        }
    }
}

#Preview {
    ContentView()
}
