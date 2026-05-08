//
//  WorkspaceModels.swift
//  LiquidCoder
//
//  Created by Reom Nagasaka on 2026/04/30.
//

import Foundation

struct CodexProject: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var rootPath: String
    var bookmarkData: Data?
    var branch: String
    var sessions: [CodexSession]
    var workspaces: [CodexWorkspace]

    init(
        id: UUID = UUID(),
        name: String,
        rootPath: String,
        bookmarkData: Data? = nil,
        branch: String = "unknown",
        sessions: [CodexSession] = [],
        workspaces: [CodexWorkspace] = []
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.bookmarkData = bookmarkData
        self.branch = branch
        self.sessions = sessions
        self.workspaces = workspaces
    }

    var rootURL: URL {
        URL(fileURLWithPath: rootPath)
    }

    var resolvedRootURL: URL {
        guard let bookmarkData else {
            return rootURL
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return rootURL
        }

        return url
    }

    func workspace(id: CodexWorkspace.ID?) -> CodexWorkspace? {
        guard let id else {
            return nil
        }

        return workspaces.first { $0.id == id }
    }

    mutating func upsertWorkspace(_ workspace: CodexWorkspace) {
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index] = workspace
        } else {
            workspaces.append(workspace)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case rootPath
        case bookmarkData
        case branch
        case sessions
        case workspaces
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        rootPath = try container.decode(String.self, forKey: .rootPath)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        branch = try container.decodeIfPresent(String.self, forKey: .branch) ?? "unknown"
        sessions = try container.decodeIfPresent([CodexSession].self, forKey: .sessions) ?? []
        workspaces = try container.decodeIfPresent([CodexWorkspace].self, forKey: .workspaces) ?? []
    }
}

struct CodexWorkspace: Codable, Identifiable, Hashable {
    var id: UUID
    var projectID: CodexProject.ID
    var sessionID: CodexSession.ID
    var branchName: String
    var worktreePath: String
    var baseRef: String
    var isArchived: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        projectID: CodexProject.ID,
        sessionID: CodexSession.ID,
        branchName: String,
        worktreePath: String,
        baseRef: String,
        isArchived: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.projectID = projectID
        self.sessionID = sessionID
        self.branchName = branchName
        self.worktreePath = worktreePath
        self.baseRef = baseRef
        self.isArchived = isArchived
        self.createdAt = createdAt
    }

    var worktreeURL: URL {
        URL(fileURLWithPath: worktreePath)
    }
}

struct CodexSession: Codable, Identifiable, Hashable {
    static let placeholderTitle = "New Chat"

    var id: UUID
    var title: String
    var createdAt: Date
    var status: CodexSessionStatus
    var threadID: String?
    var workspaceID: CodexWorkspace.ID?
    var isTerminalVisible: Bool
    var messages: [ChatMessage]
    var terminalEvents: [TerminalEvent]
    var lastCommand: String?
    var failureSummary: String?

    init(
        id: UUID = UUID(),
        title: String = CodexSession.placeholderTitle,
        createdAt: Date = .now,
        status: CodexSessionStatus = .idle,
        threadID: String? = nil,
        workspaceID: CodexWorkspace.ID? = nil,
        isTerminalVisible: Bool = false,
        messages: [ChatMessage] = [],
        terminalEvents: [TerminalEvent] = [],
        lastCommand: String? = nil,
        failureSummary: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.status = status
        self.threadID = threadID
        self.workspaceID = workspaceID
        self.isTerminalVisible = isTerminalVisible
        self.messages = messages
        self.terminalEvents = terminalEvents
        self.lastCommand = lastCommand
        self.failureSummary = failureSummary
    }

    var isUntitled: Bool {
        title == Self.placeholderTitle
    }

    var lastPrompt: String? {
        messages.reversed().first(where: { $0.role == .user })?.text
    }

    var isLegacyWithoutWorkspace: Bool {
        workspaceID == nil && (
            threadID != nil ||
            !messages.isEmpty ||
            !terminalEvents.isEmpty ||
            lastCommand != nil
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case status
        case threadID
        case workspaceID
        case isTerminalVisible
        case messages
        case terminalEvents
        case lastCommand
        case failureSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? Self.placeholderTitle
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        status = try container.decodeIfPresent(CodexSessionStatus.self, forKey: .status) ?? .waitingForInput
        threadID = try container.decodeIfPresent(String.self, forKey: .threadID)
        workspaceID = try container.decodeIfPresent(UUID.self, forKey: .workspaceID)
        isTerminalVisible = try container.decodeIfPresent(Bool.self, forKey: .isTerminalVisible) ?? false
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        terminalEvents = try container.decodeIfPresent([TerminalEvent].self, forKey: .terminalEvents) ?? []
        lastCommand = try container.decodeIfPresent(String.self, forKey: .lastCommand)
        failureSummary = try container.decodeIfPresent(String.self, forKey: .failureSummary)
    }
}

struct ChatMessage: Codable, Identifiable, Hashable {
    var id: UUID
    var role: ChatRole
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), role: ChatRole, text: String, createdAt: Date = .now) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

struct TerminalEvent: Codable, Identifiable, Hashable {
    var id: UUID
    var sessionID: CodexSession.ID
    var createdAt: Date
    var stream: TerminalEventStream
    var text: String
    var parsedEventType: String?

    init(
        id: UUID = UUID(),
        sessionID: CodexSession.ID,
        createdAt: Date = .now,
        stream: TerminalEventStream,
        text: String,
        parsedEventType: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.stream = stream
        self.text = text
        self.parsedEventType = parsedEventType
    }
}

enum ChatRole: String, Codable, Hashable {
    case user
    case codex
    case system
}

enum TerminalEventStream: String, Codable, Hashable {
    case stdout
    case stderr
    case system
}

enum CodexSessionStatus: String, Codable, Hashable {
    case idle
    case launching
    case running
    case waitingForInput
    case completed
    case failed
    case cancelled

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? Self.waitingForInput.rawValue

        switch rawValue {
        case "created":
            self = .idle
        case Self.idle.rawValue:
            self = .idle
        case Self.launching.rawValue:
            self = .launching
        case Self.running.rawValue:
            self = .running
        case Self.waitingForInput.rawValue:
            self = .waitingForInput
        case Self.completed.rawValue:
            self = .completed
        case Self.failed.rawValue:
            self = .failed
        case Self.cancelled.rawValue:
            self = .cancelled
        default:
            self = .waitingForInput
        }
    }

    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .launching:
            return "Launching"
        case .running:
            return "Running"
        case .waitingForInput:
            return "Ready"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "clock"
        case .launching:
            return "bolt.horizontal.circle"
        case .running:
            return "waveform"
        case .waitingForInput:
            return "ellipsis.bubble"
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "xmark.octagon"
        case .cancelled:
            return "slash.circle"
        }
    }
}

enum ProjectStore {
    private static let key = "liquidcoder.projects"

    static func load() -> [CodexProject] {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return []
        }

        guard let projects = try? JSONDecoder().decode([CodexProject].self, from: data) else {
            return []
        }

        return normalize(projects)
    }

    static func save(_ projects: [CodexProject]) {
        guard let data = try? JSONEncoder().encode(projects) else {
            return
        }

        UserDefaults.standard.set(data, forKey: key)
    }

    private static func normalize(_ projects: [CodexProject]) -> [CodexProject] {
        projects.map { project in
            var normalized = project

            normalized.sessions = project.sessions.map { session in
                var session = session

                if session.status == .launching || session.status == .running {
                    session.status = .cancelled
                    if session.failureSummary == nil {
                        session.failureSummary = "LiquidCoder closed while this session was active. Relaunch the session manually."
                    }
                }

                if session.isLegacyWithoutWorkspace {
                    session.status = .failed
                    session.failureSummary = session.failureSummary ?? "Legacy session from before workspace isolation. Create a new session to continue safely."
                }

                if let workspace = normalized.workspace(id: session.workspaceID) {
                    if !FileManager.default.fileExists(atPath: workspace.worktreePath) {
                        session.status = .failed
                        session.failureSummary = "Workspace worktree is missing at \(workspace.worktreePath). Create a new session or rebuild the workspace."
                    }
                }

                return session
            }

            return normalized
        }
    }
}
