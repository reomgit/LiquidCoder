//
//  SideView.swift
//  LiquidCoder
//
//  Created by Reom Nagasaka on 2026/04/30.
//

import SwiftUI

struct SideView: View {
    let projects: [CodexProject]
    @Binding var selectedSessionID: CodexSession.ID?
    @Binding var expandedProjectIDs: Set<CodexProject.ID>
    let addProject: () -> Void
    let toggleProjectExpansion: (CodexProject.ID) -> Void
    let selectSession: (CodexProject.ID, CodexSession.ID) -> Void
    let createSession: (CodexProject.ID) -> Void
    let setProjectWorkspaceMode: (CodexProject.ID, ProjectWorkspaceMode) -> Void

    var body: some View {
        List {
            Section("Projects") {
                if projects.isEmpty {
                    ContentUnavailableView(
                        "No Projects",
                        systemImage: "folder",
                        description: Text("Add a local folder to start.")
                    )
                    .frame(minHeight: 120)
                } else {
                    ForEach(projects) { project in
                        ProjectSidebarGroup(
                            project: project,
                            selectedSessionID: selectedSessionID,
                            isExpanded: expandedProjectIDs.contains(project.id),
                            toggleProjectExpansion: toggleProjectExpansion,
                            selectSession: selectSession,
                            createSession: createSession,
                            setProjectWorkspaceMode: setProjectWorkspaceMode
                        )
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("LiquidCoder")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: addProject) {
                    Label("Add Project", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.glass)
            }
        }
        .animation(.snappy(duration: 0.24, extraBounce: 0.08), value: expandedProjectIDs)
        .animation(.easeInOut(duration: 0.18), value: selectedSessionID)
    }
}

private struct ProjectSidebarGroup: View {
    let project: CodexProject
    let selectedSessionID: CodexSession.ID?
    let isExpanded: Bool
    let toggleProjectExpansion: (CodexProject.ID) -> Void
    let selectSession: (CodexProject.ID, CodexSession.ID) -> Void
    let createSession: (CodexProject.ID) -> Void
    let setProjectWorkspaceMode: (CodexProject.ID, ProjectWorkspaceMode) -> Void
    @State private var isProjectHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy(duration: 0.24, extraBounce: 0.1)) {
                        toggleProjectExpansion(project.id)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(.snappy(duration: 0.22), value: isExpanded)

                        Label(project.name, systemImage: isExpanded ? "folder.fill" : "folder")
                            .foregroundStyle(.primary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressablePlainButtonStyle())

                Menu {
                    ForEach(ProjectWorkspaceMode.allCases, id: \.self) { mode in
                        Button {
                            setProjectWorkspaceMode(project.id, mode)
                        } label: {
                            if project.workspaceMode == mode {
                                Label(mode.label, systemImage: "checkmark")
                            } else {
                                Text(mode.label)
                            }
                        }
                    }
                } label: {
                    Label(
                        project.workspaceMode.label,
                        systemImage: project.workspaceMode == .shared ? "square.3.layers.3d.down.right.fill" : "square.split.2x2"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.symbolEffect(.replace))
                }
                .menuStyle(.borderlessButton)
                .help(project.workspaceMode.shortDescription)

                Button {
                    createSession(project.id)
                } label: {
                    Image(systemName: isProjectHovered ? "square.and.pencil.circle.fill" : "square.and.pencil")
                        .foregroundStyle(isProjectHovered ? Color.accentColor : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PressablePlainButtonStyle(pressedScale: 0.92))
                .help("New Chat")
            }
            .onHover { isHovering in
                withAnimation(.easeInOut(duration: 0.14)) {
                    isProjectHovered = isHovering
                }
            }

            Text(project.workspaceMode.shortDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 24)

            if isExpanded {
                if project.sessions.isEmpty {
                    Button {
                        createSession(project.id)
                    } label: {
                        Label("New Chat", systemImage: "plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 24)
                    }
                    .buttonStyle(PressablePlainButtonStyle())
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    ForEach(project.sessions) { session in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectSession(project.id, session.id)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: icon(for: session))
                                    .foregroundStyle(selectedSessionID == session.id ? .primary : .secondary)
                                    .contentTransition(.symbolEffect(.replace))
                                Text(session.title)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.caption)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(rowBackground(for: session), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .padding(.leading, 20)
                        }
                        .buttonStyle(PressablePlainButtonStyle())
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func rowBackground(for session: CodexSession) -> Color {
        selectedSessionID == session.id ? Color.accentColor.opacity(0.16) : .clear
    }

    private func icon(for session: CodexSession) -> String {
        if selectedSessionID == session.id {
            return "bubble.left.and.bubble.right.fill"
        }

        switch session.status {
        case .running, .launching:
            return "waveform.circle.fill"
        case .waitingForInput:
            return "pause.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .cancelled:
            return "slash.circle.fill"
        case .idle:
            return "bubble.left.and.bubble.right"
        }
    }
}
