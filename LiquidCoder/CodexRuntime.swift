//
//  CodexRuntime.swift
//  LiquidCoder
//
//  Created by OpenAI Codex on 2026/04/30.
//

import Combine
import Darwin
import Foundation

@MainActor
final class CodexRuntime: ObservableObject {
    private static let bundledShellPath = "/bin/zsh"
    private static let defaultSearchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]
    struct PreparedSessionContext {
        let projectID: CodexProject.ID
        let sessionID: CodexSession.ID
        let projectRootURL: URL
        let securityScopeActive: Bool
        let workspace: CodexWorkspace
        let sourceBranch: String
        let permissionMode: CodexPermissionMode
        let codexExecutableURL: URL
    }

    enum SessionEvent {
        case status(CodexSessionStatus)
        case threadStarted(String)
        case agentMessage(String)
        case commandStarted(String)
        case terminalEvent(TerminalEvent)
        case failed(String)
    }

    enum RuntimeError: LocalizedError {
        case missingCodexCLI
        case missingGitCLI
        case workspace(WorkspaceManager.WorkspaceError)
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingCodexCLI:
                return "LiquidCoder could not find the `codex` CLI in your terminal environment. Install it somewhere stable like `/opt/homebrew/bin/codex` or `/usr/local/bin/codex`, or set `CODEX_CLI_PATH`."
            case .missingGitCLI:
                return "LiquidCoder could not find `git`. Install the Xcode command line tools or make `git` available on PATH."
            case .workspace(let error):
                return error.localizedDescription
            case .launchFailed(let details):
                return "LiquidCoder failed to launch the Codex session. \(details)"
            }
        }
    }

    private struct RunningSession {
        let projectID: CodexProject.ID
        let sessionTitle: String
        let workspaceID: CodexWorkspace.ID
        let workspaceScope: CodexWorkspaceScope
        let process: Process
        let reader: PTYReader
        let masterHandle: FileHandle
        let slaveInputHandle: FileHandle
        let slaveOutputHandle: FileHandle
        let slaveErrorHandle: FileHandle
        let projectRootURL: URL
        let securityScopeActive: Bool
        let onEvent: @MainActor (SessionEvent) -> Void
        var diagnostics: [String] = []
        var sawTurnCompletion = false
        var requestedStop = false
    }

    @Published private(set) var activeSessionIDs: Set<CodexSession.ID> = []

    private let workspaceManager = WorkspaceManager()
    private var runningSessions: [CodexSession.ID: RunningSession] = [:]

    func hasActiveSession(for sessionID: CodexSession.ID) -> Bool {
        activeSessionIDs.contains(sessionID)
    }

    func prepareWorkspace(for session: CodexSession, in project: CodexProject) throws -> PreparedSessionContext {
        let projectRootURL = project.resolvedRootURL
        let securityScopeActive = projectRootURL.startAccessingSecurityScopedResource()

        do {
            guard let codexExecutableURL = resolveExecutableURL(named: "codex") else {
                throw RuntimeError.missingCodexCLI
            }
            guard resolveExecutableURL(named: "git") != nil else {
                throw RuntimeError.missingGitCLI
            }

            let context = try workspaceManager.prepareWorkspace(for: session, in: project)
            return PreparedSessionContext(
                projectID: project.id,
                sessionID: session.id,
                projectRootURL: projectRootURL,
                securityScopeActive: securityScopeActive,
                workspace: context.workspace,
                sourceBranch: context.sourceBranch,
                permissionMode: project.permissionMode,
                codexExecutableURL: codexExecutableURL
            )
        } catch let error as RuntimeError {
            if securityScopeActive {
                projectRootURL.stopAccessingSecurityScopedResource()
            }
            throw error
        } catch let error as WorkspaceManager.WorkspaceError {
            if securityScopeActive {
                projectRootURL.stopAccessingSecurityScopedResource()
            }
            throw RuntimeError.workspace(error)
        } catch {
            if securityScopeActive {
                projectRootURL.stopAccessingSecurityScopedResource()
            }
            throw RuntimeError.launchFailed(error.localizedDescription)
        }
    }

    func startSession(
        session: CodexSession,
        context: PreparedSessionContext,
        prompt: String,
        onEvent: @escaping @MainActor (SessionEvent) -> Void
    ) {
        launchSession(
            session: session,
            context: context,
            prompt: prompt,
            isResume: false,
            onEvent: onEvent
        )
    }

    func resumeSession(
        session: CodexSession,
        context: PreparedSessionContext,
        prompt: String,
        onEvent: @escaping @MainActor (SessionEvent) -> Void
    ) {
        launchSession(
            session: session,
            context: context,
            prompt: prompt,
            isResume: true,
            onEvent: onEvent
        )
    }

    func stopSession(_ sessionID: CodexSession.ID) {
        guard var runningSession = runningSessions[sessionID] else {
            return
        }

        runningSession.requestedStop = true
        runningSessions[sessionID] = runningSession
        runningSession.process.terminate()
    }

    private func launchSession(
        session: CodexSession,
        context: PreparedSessionContext,
        prompt: String,
        isResume: Bool,
        onEvent: @escaping @MainActor (SessionEvent) -> Void
    ) {
        guard !activeSessionIDs.contains(session.id) else {
            onEvent(.failed("This session is already running. Wait for Codex to finish or stop it before sending another prompt."))
            releaseSecurityScope(for: context)
            return
        }

        do {
            if let conflictMessage = sharedWorkspaceConflict(context: context) {
                onEvent(.failed(conflictMessage))
                releaseSecurityScope(for: context)
                return
            }

            let launch = try makeLaunchHandles()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: Self.bundledShellPath)
            process.arguments = [
                "-lc",
                shellCommand(
                    permissionMode: context.permissionMode,
                    workspacePath: context.workspace.worktreePath,
                    isResume: isResume,
                    threadID: session.threadID
                )
            ]
            process.currentDirectoryURL = context.workspace.worktreeURL
            process.standardInput = launch.slaveInputHandle
            process.standardOutput = launch.slaveOutputHandle
            process.standardError = launch.slaveErrorHandle
            process.environment = launchEnvironment(
                session: session,
                prompt: prompt,
                workspace: context.workspace,
                codexExecutablePath: context.codexExecutableURL.path
            )

            let sessionID = session.id
            let reader = PTYReader(fileHandle: launch.masterHandle)
            reader.onLine = { [weak self] line in
                DispatchQueue.main.async {
                    self?.handleTerminalLine(
                        line,
                        sessionID: sessionID,
                        parsedStream: .stdout
                    )
                }
            }

            process.terminationHandler = { [weak self] terminatedProcess in
                DispatchQueue.main.async {
                    self?.handleTermination(of: sessionID, process: terminatedProcess)
                }
            }

            let commandArguments = codexLaunchArguments(
                permissionMode: context.permissionMode,
                workspacePath: context.workspace.worktreePath,
                isResume: isResume,
                threadID: session.threadID
            )
            let command = """
            $ cd \(context.workspace.worktreePath)
            $ \(context.codexExecutableURL.path) \(commandArguments.joined(separator: " ")) <prompt>
            """

            runningSessions[sessionID] = RunningSession(
                projectID: context.projectID,
                sessionTitle: session.title,
                workspaceID: context.workspace.id,
                workspaceScope: context.workspace.scope,
                process: process,
                reader: reader,
                masterHandle: launch.masterHandle,
                slaveInputHandle: launch.slaveInputHandle,
                slaveOutputHandle: launch.slaveOutputHandle,
                slaveErrorHandle: launch.slaveErrorHandle,
                projectRootURL: context.projectRootURL,
                securityScopeActive: context.securityScopeActive,
                onEvent: onEvent
            )
            activeSessionIDs.insert(sessionID)

            onEvent(.status(.launching))
            onEvent(.commandStarted(command))
            onEvent(.terminalEvent(TerminalEvent(
                sessionID: sessionID,
                stream: .system,
                text: command,
                parsedEventType: "command.started"
            )))

            try process.run()
            reader.start()
            close(launch.slaveFD)
        } catch let error as RuntimeError {
            releaseSecurityScope(for: context)
            onEvent(.failed(error.localizedDescription))
        } catch {
            releaseSecurityScope(for: context)
            onEvent(.failed("LiquidCoder failed to launch the session process. \(error.localizedDescription)"))
        }
    }

    private func sharedWorkspaceConflict(context: PreparedSessionContext) -> String? {
        guard context.workspace.scope == .shared else {
            return nil
        }

        guard let active = runningSessions.values.first(where: {
            $0.projectID == context.projectID
                && $0.workspaceScope == .shared
                && $0.workspaceID == context.workspace.id
                && $0.process.isRunning
        }) else {
            return nil
        }

        return "Shared mode reuses one branch and one worktree for this project. `\(active.sessionTitle)` is already running there. Stop that session or switch the project back to Isolated mode before launching another chat."
    }

    private func resolveExecutableURL(named executable: String) -> URL? {
        let environment = ProcessInfo.processInfo.environment

        if executable == "codex",
           let explicitPath = environment["CODEX_CLI_PATH"],
           canExecute(path: explicitPath) {
            return URL(fileURLWithPath: explicitPath)
        }

        let pathEntries = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let candidates = pathEntries + Self.defaultSearchPaths

        for directory in candidates {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(executable).path
            if canExecute(path: path) {
                return URL(fileURLWithPath: path)
            }
        }

        if let shellResolvedPath = resolveExecutableURLUsingLoginShell(named: executable) {
            return shellResolvedPath
        }

        return nil
    }

    private func canExecute(path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
            || access(path, X_OK) == 0
    }

    private func resolveExecutableURLUsingLoginShell(named executable: String) -> URL? {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: Self.bundledShellPath)
        process.arguments = ["-lic", "command -v -- \(shellQuoted(executable))"]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let output = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let output, !output.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: output)
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func launchEnvironment(
        session: CodexSession,
        prompt: String,
        workspace: CodexWorkspace,
        codexExecutablePath: String
    ) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let currentEntries = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let mergedEntries = Array(NSOrderedSet(array: currentEntries + Self.defaultSearchPaths)) as? [String] ?? Self.defaultSearchPaths
        environment["PATH"] = mergedEntries.joined(separator: ":")
        environment["SHELL"] = environment["SHELL"] ?? Self.bundledShellPath
        environment["LC_CODEX_BIN"] = codexExecutablePath
        environment["LC_WORKTREE_ROOT"] = workspace.worktreePath
        environment["LC_PROMPT"] = prompt
        environment["LC_THREAD_ID"] = session.threadID ?? ""
        return environment
    }

    private func shellCommand(
        permissionMode: CodexPermissionMode,
        workspacePath: String,
        isResume: Bool,
        threadID: String?
    ) -> String {
        let launchArguments = codexLaunchArguments(
            permissionMode: permissionMode,
            workspacePath: workspacePath,
            isResume: isResume,
            threadID: threadID
        )
            .map(shellQuoted)
            .joined(separator: " ")

        return """
        cd -- "$LC_WORKTREE_ROOT" || exit 1
        exec "$LC_CODEX_BIN" \(launchArguments) "$LC_PROMPT"
        """
    }

    private func codexLaunchArguments(
        permissionMode: CodexPermissionMode,
        workspacePath: String,
        isResume: Bool,
        threadID: String?
    ) -> [String] {
        var arguments = ["--cd", workspacePath, "exec"]

        if isResume, let threadID, !threadID.isEmpty {
            arguments.append("resume")
            arguments.append("--json")
            arguments.append(contentsOf: permissionArguments(for: permissionMode))
            arguments.append("--skip-git-repo-check")
            arguments.append(threadID)
            return arguments
        }

        arguments.append("--json")
        arguments.append("--color")
        arguments.append("never")
        arguments.append(contentsOf: permissionArguments(for: permissionMode))
        arguments.append("--skip-git-repo-check")
        return arguments
    }

    private func permissionArguments(for mode: CodexPermissionMode) -> [String] {
        switch mode {
        case .defaultConfig:
            return []
        case .manualReview:
            return ["--sandbox", "danger-full-access", "--ask-for-approval", "untrusted"]
        case .fullAccess:
            return ["--dangerously-bypass-approvals-and-sandbox"]
        }
    }

    private func handleTerminalLine(
        _ line: String,
        sessionID: CodexSession.ID,
        parsedStream: TerminalEventStream
    ) {
        guard var runningSession = runningSessions[sessionID] else {
            return
        }

        let trimmed = line.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else {
            return
        }

        if
            let data = trimmed.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String
        {
            runningSession.onEvent(.terminalEvent(TerminalEvent(
                sessionID: sessionID,
                stream: parsedStream,
                text: trimmed,
                parsedEventType: type
            )))

            switch type {
            case "thread.started":
                if let threadID = object["thread_id"] as? String {
                    runningSession.onEvent(.threadStarted(threadID))
                }
            case "turn.started":
                runningSession.onEvent(.status(.running))
            case "item.completed":
                if
                    let item = object["item"] as? [String: Any],
                    let itemType = item["type"] as? String,
                    itemType == "agent_message",
                    let text = item["text"] as? String,
                    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    runningSession.onEvent(.agentMessage(text))
                }
            case "turn.completed":
                runningSession.sawTurnCompletion = true
                runningSession.onEvent(.status(.waitingForInput))
            default:
                break
            }

            runningSessions[sessionID] = runningSession
            return
        }

        if shouldSurfaceTerminalLine(trimmed) {
            runningSession.onEvent(.terminalEvent(TerminalEvent(
                sessionID: sessionID,
                stream: parsedStream,
                text: trimmed,
                parsedEventType: nil
            )))

            runningSession.diagnostics.append(trimmed)
            if runningSession.diagnostics.count > 60 {
                runningSession.diagnostics.removeFirst(runningSession.diagnostics.count - 60)
            }
        }

        runningSessions[sessionID] = runningSession
    }

    private func handleTermination(of sessionID: CodexSession.ID, process: Process) {
        guard let runningSession = runningSessions.removeValue(forKey: sessionID) else {
            return
        }

        activeSessionIDs.remove(sessionID)
        runningSession.reader.stop()
        closeHandles(for: runningSession)

        if runningSession.securityScopeActive {
            runningSession.projectRootURL.stopAccessingSecurityScopedResource()
        }

        if runningSession.requestedStop {
            runningSession.onEvent(.status(.cancelled))
            runningSession.onEvent(.terminalEvent(TerminalEvent(
                sessionID: sessionID,
                stream: .system,
                text: "Session stopped by LiquidCoder.",
                parsedEventType: "session.cancelled"
            )))
            return
        }

        guard process.terminationStatus == 0 else {
            let summary = runningSession.diagnostics.last
                ?? "Codex exited with status \(process.terminationStatus)."
            runningSession.onEvent(.failed(summary))
            return
        }

        if !runningSession.sawTurnCompletion {
            runningSession.onEvent(.status(.completed))
        }
    }

    private func shouldSurfaceTerminalLine(_ line: String) -> Bool {
        if line.hasPrefix("{") {
            return false
        }

        let noisyPrefixes = [
            "202",
            "<html>",
            "<head>",
            "<body>",
            "<div",
            "<svg",
            "<path",
            "</"
        ]
        let noisySubstrings = [
            "codex_analytics::client",
            "codex_core::plugins::manifest",
            "Enable JavaScript and cookies to continue",
            "challenge-platform"
        ]

        if noisyPrefixes.contains(where: { line.hasPrefix($0) }) {
            return line.contains("error:") || line.contains("No such file or directory")
        }

        if noisySubstrings.contains(where: { line.contains($0) }) {
            return false
        }

        return true
    }

    private func releaseSecurityScope(for context: PreparedSessionContext) {
        if context.securityScopeActive {
            context.projectRootURL.stopAccessingSecurityScopedResource()
        }
    }

    private func closeHandles(for session: RunningSession) {
        session.masterHandle.readabilityHandler = nil
        try? session.masterHandle.close()
        try? session.slaveInputHandle.close()
        try? session.slaveOutputHandle.close()
        try? session.slaveErrorHandle.close()
    }

    private func makeLaunchHandles() throws -> PTYLaunchHandles {
        var masterFD: Int32 = 0
        var slaveFD: Int32 = 0

        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            throw RuntimeError.launchFailed(String(cString: strerror(errno)))
        }

        guard
            let slaveInput = FileHandle(validatingDescriptor: dup(slaveFD)),
            let slaveOutput = FileHandle(validatingDescriptor: dup(slaveFD)),
            let slaveError = FileHandle(validatingDescriptor: dup(slaveFD)),
            let masterHandle = FileHandle(validatingDescriptor: masterFD)
        else {
            close(masterFD)
            close(slaveFD)
            throw RuntimeError.launchFailed("Failed to allocate terminal descriptors.")
        }

        return PTYLaunchHandles(
            masterHandle: masterHandle,
            slaveInputHandle: slaveInput,
            slaveOutputHandle: slaveOutput,
            slaveErrorHandle: slaveError,
            slaveFD: slaveFD
        )
    }
}

private struct PTYLaunchHandles {
    let masterHandle: FileHandle
    let slaveInputHandle: FileHandle
    let slaveOutputHandle: FileHandle
    let slaveErrorHandle: FileHandle
    let slaveFD: Int32
}

private final class PTYReader {
    let fileHandle: FileHandle
    var onLine: ((String) -> Void)?

    private var buffer = Data()

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    func start() {
        fileHandle.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
    }

    func stop() {
        fileHandle.readabilityHandler = nil
        flushBuffer()
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else {
            flushBuffer()
            return
        }

        buffer.append(data)

        while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
            buffer.removeSubrange(0...newlineRange.lowerBound)

            let line = String(data: lineData, encoding: .utf8)?
                .replacingOccurrences(of: "\r", with: "")
            if let line, !line.isEmpty {
                onLine?(line)
            }
        }
    }

    private func flushBuffer() {
        guard !buffer.isEmpty else {
            return
        }

        defer { buffer.removeAll(keepingCapacity: false) }

        let line = String(data: buffer, encoding: .utf8)?
            .replacingOccurrences(of: "\r", with: "")
        if let line, !line.isEmpty {
            onLine?(line)
        }
    }
}

private extension FileHandle {
    convenience init?(validatingDescriptor descriptor: Int32) {
        guard descriptor >= 0 else {
            return nil
        }

        self.init(fileDescriptor: descriptor, closeOnDealloc: true)
    }
}
