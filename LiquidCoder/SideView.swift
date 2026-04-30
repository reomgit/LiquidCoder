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
                            createSession: createSession
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
    }
}

private struct ProjectSidebarGroup: View {
    let project: CodexProject
    let selectedSessionID: CodexSession.ID?
    let isExpanded: Bool
    let toggleProjectExpansion: (CodexProject.ID) -> Void
    let selectSession: (CodexProject.ID, CodexSession.ID) -> Void
    let createSession: (CodexProject.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    toggleProjectExpansion(project.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Label(project.name, systemImage: "folder")
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    createSession(project.id)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New Chat")
            }

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
                    .buttonStyle(.plain)
                } else {
                    ForEach(project.sessions) { session in
                        Button {
                            selectSession(project.id, session.id)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: session.status.systemImage)
                                    .foregroundStyle(selectedSessionID == session.id ? .primary : .secondary)
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
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func rowBackground(for session: CodexSession) -> Color {
        selectedSessionID == session.id ? Color.accentColor.opacity(0.16) : .clear
    }
}
