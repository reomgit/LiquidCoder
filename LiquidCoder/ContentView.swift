//
//  ContentView.swift
//  LiquidCoder
//
//  Created by Reom Nagasaka on 2026/04/30.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var runtime: CodexRuntime

    @State private var selectedSessionID: CodexSession.ID?
    @State private var expandedProjectIDs: Set<CodexProject.ID> = []
    @State private var draftPrompt = ""
    @StateObject private var terminalStore = SessionTerminalStore()

    private var selectedSessionLocation: (projectIndex: Int, sessionIndex: Int)? {
        appState.location(for: selectedSessionID)
    }

    var body: some View {
        NavigationSplitView {
            SideView(
                projects: appState.projects,
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
                let projectBinding = bindingForProject(at: selectedSessionLocation.projectIndex)
                let sessionBinding = bindingForSession(at: selectedSessionLocation)
                let session = appState.projects[selectedSessionLocation.projectIndex].sessions[selectedSessionLocation.sessionIndex]
                let project = appState.projects[selectedSessionLocation.projectIndex]

                ProjectChatView(
                    project: projectBinding,
                    session: sessionBinding,
                    workspace: project.workspace(id: session.workspaceID),
                    runtime: runtime,
                    terminalStore: terminalStore,
                    draftPrompt: $draftPrompt,
                    sendPrompt: sendPrompt
                )
            } else if appState.projects.isEmpty {
                EmptyProjectView(addProject: addProject)
            } else {
                EmptySessionView()
            }
        }
        .frame(minWidth: 880, minHeight: 700)
        .onAppear {
            appState.refreshProjectBranches()
            syncSidebarState(with: appState.projects)
        }
        .onChange(of: appState.projects) { _, newValue in
            syncSidebarState(with: newValue)
        }
        .focusedSceneValue(\.sendPromptAction, sendPrompt)
        .focusedSceneValue(\.newChatAction, createChatFromShortcut)
        .focusedSceneValue(\.newProjectAction, addProject)
    }

    private func bindingForProject(at index: Int) -> Binding<CodexProject> {
        Binding(
            get: { appState.projects[index] },
            set: { appState.projects[index] = $0 }
        )
    }

    private func bindingForSession(at location: (projectIndex: Int, sessionIndex: Int)) -> Binding<CodexSession> {
        Binding(
            get: { appState.projects[location.projectIndex].sessions[location.sessionIndex] },
            set: { appState.projects[location.projectIndex].sessions[location.sessionIndex] = $0 }
        )
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

        switch appState.addProject(at: url) {
        case .added(let projectID):
            expandedProjectIDs.insert(projectID)
            draftPrompt = ""
        case .existing(let projectID, let firstSessionID):
            expandedProjectIDs.insert(projectID)
            if let firstSessionID {
                selectedSessionID = firstSessionID
            }
        }
    }

    private func sendPrompt() {
        let prompt = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, let selectedSessionID else {
            return
        }

        guard !runtime.hasActiveSession(for: selectedSessionID) else {
            return
        }

        guard let startingState = appState.markSessionStarting(sessionID: selectedSessionID, prompt: prompt) else {
            return
        }

        draftPrompt = ""

        do {
            let context = try runtime.prepareWorkspace(for: startingState.session, in: startingState.project)
            guard let latestSession = appState.applyPreparedWorkspace(context, to: selectedSessionID) else {
                return
            }

            if latestSession.threadID?.isEmpty == false {
                runtime.resumeSession(session: latestSession, context: context, prompt: prompt) { event in
                    appState.apply(event, sessionID: latestSession.id, projectID: context.projectID)
                }
            } else {
                runtime.startSession(session: latestSession, context: context, prompt: prompt) { event in
                    appState.apply(event, sessionID: latestSession.id, projectID: context.projectID)
                }
            }
        } catch {
            appState.failSession(selectedSessionID, summary: error.localizedDescription)
        }
    }

    private func toggleProjectExpansion(_ projectID: CodexProject.ID) {
        withAnimation(.snappy(duration: 0.24, extraBounce: 0.1)) {
            if expandedProjectIDs.contains(projectID) {
                expandedProjectIDs.remove(projectID)
            } else {
                expandedProjectIDs.insert(projectID)
            }
        }
    }

    private func selectSession(projectID: CodexProject.ID, sessionID: CodexSession.ID) {
        withAnimation(.easeInOut(duration: 0.18)) {
            expandedProjectIDs.insert(projectID)
            selectedSessionID = sessionID
        }
    }

    private func createSession(projectID: CodexProject.ID) {
        guard let sessionID = appState.createSession(projectID: projectID) else {
            return
        }

        withAnimation(.snappy(duration: 0.24, extraBounce: 0.08)) {
            expandedProjectIDs.insert(projectID)
            selectedSessionID = sessionID
        }
        draftPrompt = ""
    }

    private func createChatFromShortcut() {
        if let selectedSessionID,
           let location = appState.location(for: selectedSessionID) {
            createSession(projectID: appState.projects[location.projectIndex].id)
            return
        }

        guard let firstProjectID = appState.projects.first?.id else {
            return
        }

        createSession(projectID: firstProjectID)
    }

    private func syncSidebarState(with projects: [CodexProject]) {
        let availableProjectIDs = Set(projects.map(\.id))
        expandedProjectIDs = expandedProjectIDs.intersection(availableProjectIDs)

        if expandedProjectIDs.isEmpty, let firstProject = projects.first {
            expandedProjectIDs.insert(firstProject.id)
        }

        if appState.containsSession(selectedSessionID) {
            return
        }

        if let firstExistingSession = appState.firstSessionReference() {
            selectedSessionID = firstExistingSession.sessionID
            expandedProjectIDs.insert(firstExistingSession.projectID)
        } else {
            selectedSessionID = nil
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(CodexRuntime())
}
