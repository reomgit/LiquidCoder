//
//  WorkspaceManager.swift
//  LiquidCoder
//
//  Created by OpenAI Codex on 2026/04/30.
//

import Foundation

struct WorkspaceManager {
    struct WorkspaceContext {
        let workspace: CodexWorkspace
        let sourceBranch: String
    }

    enum WorkspaceError: LocalizedError {
        case gitNotFound
        case invalidProjectRoot(String)
        case notGitRepository(String)
        case branchLookupFailed(String)
        case worktreeMissing(String)
        case sharedWorkspaceMissing(String)
        case worktreeCreationFailed(String)
        case excludeUpdateFailed(String)

        var errorDescription: String? {
            switch self {
            case .gitNotFound:
                return "LiquidCoder could not find `git`. Install the Xcode command line tools or make `git` available on PATH."
            case .invalidProjectRoot(let path):
                return "Selected project root does not exist at \(path)."
            case .notGitRepository(let path):
                return "LiquidCoder can only isolate sessions inside a git repo. `\(path)` is not a git repository."
            case .branchLookupFailed(let details):
                return "LiquidCoder could not determine the source branch for this project. \(details)"
            case .worktreeMissing(let path):
                return "Session workspace is missing at \(path). LiquidCoder will not fall back to the main project root."
            case .sharedWorkspaceMissing(let path):
                return "Shared project workspace is missing at \(path). LiquidCoder will not silently switch roots."
            case .worktreeCreationFailed(let details):
                return "LiquidCoder failed to create the session worktree. \(details)"
            case .excludeUpdateFailed(let details):
                return "LiquidCoder could not update `.git/info/exclude` for workspace metadata. \(details)"
            }
        }
    }

    private let fileManager = FileManager.default
    private let gitExecutableURL: URL

    init(gitExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/git")) {
        self.gitExecutableURL = gitExecutableURL
    }

    func prepareWorkspace(for session: CodexSession, in project: CodexProject) throws -> WorkspaceContext {
        let rootURL = project.resolvedRootURL
        guard fileManager.fileExists(atPath: rootURL.path) else {
            throw WorkspaceError.invalidProjectRoot(rootURL.path)
        }

        guard fileManager.isExecutableFile(atPath: gitExecutableURL.path) else {
            throw WorkspaceError.gitNotFound
        }

        guard isGitRepository(rootURL: rootURL) else {
            throw WorkspaceError.notGitRepository(rootURL.path)
        }

        let sourceBranch = try resolveSourceBranch(rootURL: rootURL)

        switch project.workspaceMode {
        case .isolated:
            return try prepareIsolatedWorkspace(
                for: session,
                in: project,
                rootURL: rootURL,
                sourceBranch: sourceBranch
            )
        case .shared:
            return try prepareSharedWorkspace(
                for: session,
                in: project,
                rootURL: rootURL,
                sourceBranch: sourceBranch
            )
        }
    }

    private func prepareIsolatedWorkspace(
        for session: CodexSession,
        in project: CodexProject,
        rootURL: URL,
        sourceBranch: String
    ) throws -> WorkspaceContext {
        if let workspaceID = session.workspaceID, let existing = project.workspace(id: workspaceID) {
            guard fileManager.fileExists(atPath: existing.worktreePath) else {
                throw WorkspaceError.worktreeMissing(existing.worktreePath)
            }
            return WorkspaceContext(workspace: existing, sourceBranch: sourceBranch)
        }

        try ensureWorktreeMetadataIgnored(rootURL: rootURL)

        let workspaceRootURL = rootURL
            .appendingPathComponent(".liquidcoder", isDirectory: true)
            .appendingPathComponent("workspaces", isDirectory: true)
        try fileManager.createDirectory(at: workspaceRootURL, withIntermediateDirectories: true)

        let slug = session.id.uuidString.prefix(8).lowercased()
        let branchName = "liquidcoder/session-\(slug)"
        let worktreeURL = workspaceRootURL.appendingPathComponent(slug, isDirectory: true)

        if fileManager.fileExists(atPath: worktreeURL.path) {
            let workspace = CodexWorkspace(
                projectID: project.id,
                sessionID: session.id,
                scope: .isolated,
                branchName: branchName,
                worktreePath: worktreeURL.path,
                baseRef: sourceBranch
            )
            return WorkspaceContext(workspace: workspace, sourceBranch: sourceBranch)
        }

        let result = runGit(
            arguments: [
                "worktree", "add",
                "-b", branchName,
                worktreeURL.path,
                sourceBranch
            ],
            rootURL: rootURL
        )

        guard result.exitCode == 0 else {
            throw WorkspaceError.worktreeCreationFailed(result.summary)
        }

        let workspace = CodexWorkspace(
            projectID: project.id,
            sessionID: session.id,
            scope: .isolated,
            branchName: branchName,
            worktreePath: worktreeURL.path,
            baseRef: sourceBranch
        )
        return WorkspaceContext(workspace: workspace, sourceBranch: sourceBranch)
    }

    private func prepareSharedWorkspace(
        for session: CodexSession,
        in project: CodexProject,
        rootURL: URL,
        sourceBranch: String
    ) throws -> WorkspaceContext {
        if let workspaceID = session.workspaceID, let existing = project.workspace(id: workspaceID) {
            guard fileManager.fileExists(atPath: existing.worktreePath) else {
                throw WorkspaceError.sharedWorkspaceMissing(existing.worktreePath)
            }
            return WorkspaceContext(workspace: existing, sourceBranch: sourceBranch)
        }

        if let existing = project.sharedWorkspace {
            guard fileManager.fileExists(atPath: existing.worktreePath) else {
                throw WorkspaceError.sharedWorkspaceMissing(existing.worktreePath)
            }
            return WorkspaceContext(workspace: existing, sourceBranch: sourceBranch)
        }

        try ensureWorktreeMetadataIgnored(rootURL: rootURL)

        let workspace = CodexWorkspace(
            projectID: project.id,
            scope: .shared,
            branchName: sourceBranch,
            worktreePath: rootURL.path,
            baseRef: sourceBranch
        )
        return WorkspaceContext(workspace: workspace, sourceBranch: sourceBranch)
    }

    private func isGitRepository(rootURL: URL) -> Bool {
        let result = runGit(arguments: ["rev-parse", "--is-inside-work-tree"], rootURL: rootURL)
        return result.exitCode == 0 && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    private func resolveSourceBranch(rootURL: URL) throws -> String {
        let branchResult = runGit(arguments: ["branch", "--show-current"], rootURL: rootURL)
        let branch = branchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if branchResult.exitCode == 0, !branch.isEmpty {
            return branch
        }

        let detachedResult = runGit(arguments: ["rev-parse", "--short", "HEAD"], rootURL: rootURL)
        let detachedRef = detachedResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard detachedResult.exitCode == 0, !detachedRef.isEmpty else {
            throw WorkspaceError.branchLookupFailed(detachedResult.summary)
        }

        return detachedRef
    }

    private func ensureWorktreeMetadataIgnored(rootURL: URL) throws {
        let infoDirectoryURL = rootURL
            .appendingPathComponent(".git", isDirectory: true)
            .appendingPathComponent("info", isDirectory: true)
        let excludeURL = infoDirectoryURL.appendingPathComponent("exclude")

        do {
            try fileManager.createDirectory(at: infoDirectoryURL, withIntermediateDirectories: true)
            let marker = ".liquidcoder/"
            let existing = (try? String(contentsOf: excludeURL, encoding: .utf8)) ?? ""
            guard !existing.contains(marker) else {
                return
            }

            let prefix = existing.isEmpty || existing.hasSuffix("\n") ? existing : existing + "\n"
            try (prefix + marker + "\n").write(to: excludeURL, atomically: true, encoding: .utf8)
        } catch {
            throw WorkspaceError.excludeUpdateFailed(error.localizedDescription)
        }
    }

    private func runGit(arguments: [String], rootURL: URL) -> CommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = gitExecutableURL
        process.arguments = arguments
        process.currentDirectoryURL = rootURL
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CommandResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}

private struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var summary: String {
        let trimmedError = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedError.isEmpty {
            return trimmedError
        }

        let trimmedOutput = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOutput.isEmpty {
            return trimmedOutput
        }

        return "Process exited with status \(exitCode)."
    }
}
