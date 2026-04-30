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

    init(
        id: UUID = UUID(),
        name: String,
        rootPath: String,
        bookmarkData: Data? = nil,
        branch: String = "main",
        sessions: [CodexSession] = []
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.bookmarkData = bookmarkData
        self.branch = branch
        self.sessions = sessions
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
}

struct CodexSession: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var createdAt: Date
    var status: CodexSessionStatus
    var threadID: String?
    var failureSummary: String?
    var messages: [ChatMessage]

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        status: CodexSessionStatus = .created,
        threadID: String? = nil,
        failureSummary: String? = nil,
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.status = status
        self.threadID = threadID
        self.failureSummary = failureSummary
        self.messages = messages
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case status
        case threadID
        case failureSummary
        case messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        status = try container.decodeIfPresent(CodexSessionStatus.self, forKey: .status) ?? .completed
        threadID = try container.decodeIfPresent(String.self, forKey: .threadID)
        failureSummary = try container.decodeIfPresent(String.self, forKey: .failureSummary)
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
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

enum ChatRole: String, Codable, Hashable {
    case user
    case codex
    case system
}

enum CodexSessionStatus: String, Codable, Hashable {
    case created
    case launching
    case running
    case completed
    case failed
    case cancelled

    var label: String {
        switch self {
        case .created:
            return "Created"
        case .launching:
            return "Launching"
        case .running:
            return "Running"
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
        case .created:
            return "clock"
        case .launching:
            return "bolt.horizontal.circle"
        case .running:
            return "waveform"
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

        return (try? JSONDecoder().decode([CodexProject].self, from: data)) ?? []
    }

    static func save(_ projects: [CodexProject]) {
        guard let data = try? JSONEncoder().encode(projects) else {
            return
        }

        UserDefaults.standard.set(data, forKey: key)
    }
}
