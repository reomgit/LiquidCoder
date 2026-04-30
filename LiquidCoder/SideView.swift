//
//  SideView.swift
//  LiquidCoder
//
//  Created by Reom Nagasaka on 2026/04/30.
//

import SwiftUI

struct SideView: View {
    let projects: [CodexProject]
    @Binding var selectedProjectID: CodexProject.ID?
    let addProject: () -> Void

    var body: some View {
        List(selection: $selectedProjectID) {
            Section {
                Label("New Chat", systemImage: "square.and.pencil")
                Label("Search", systemImage: "magnifyingglass")
                Label("Plugins", systemImage: "square.grid.2x2")
            }

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
                        Label(project.name, systemImage: "folder")
                            .tag(project.id)

                        if project.id == selectedProjectID {
                            ForEach(project.sessions.prefix(4)) { session in
                                Label(session.title, systemImage: session.status.systemImage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 16)
                            }
                        }
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
