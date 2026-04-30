//
//  CodexRuntime.swift
//  LiquidCoder
//
//  Created by OpenAI Codex on 2026/04/30.
//

import Combine
import Foundation

@MainActor
final class CodexRuntime: ObservableObject {
    enum SessionEvent {
        case status(CodexSessionStatus)
        case threadStarted(String)
        case agentMessage(String)
        case failed(String)
    }

    private struct RunningSession {
        let projectID: CodexProject.ID
        let process: Process
        let stdoutReader: PipeLineReader
        let stderrReader: PipeLineReader
        let rootURL: URL
        let securityScopeActive: Bool
        let onEvent: @MainActor (SessionEvent) -> Void
        var stderrLines: [String] = []
        var didCompleteTurn = false
    }

    @Published private(set) var activeProjectIDs: Set<CodexProject.ID> = []

    private var runningSessions: [CodexSession.ID: RunningSession] = [:]

    func hasActiveSession(for projectID: CodexProject.ID) -> Bool {
        activeProjectIDs.contains(projectID)
    }

    func launch(
        project: CodexProject,
        sessionID: CodexSession.ID,
        prompt: String,
        onEvent: @escaping @MainActor (SessionEvent) -> Void
    ) {
        guard !hasActiveSession(for: project.id) else {
            onEvent(.failed("A Codex session is already running for this project. LiquidCoder blocks concurrent launches in one worktree because collision risk is real."))
            return
        }

        let rootURL = project.resolvedRootURL
        let securityScopeActive = rootURL.startAccessingSecurityScopedResource()
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "codex",
            "exec",
            "--json",
            "--color",
            "never",
            "--full-auto",
            "--skip-git-repo-check",
            "-C",
            rootURL.path,
            prompt
        ]
        process.currentDirectoryURL = rootURL
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutReader = PipeLineReader(fileHandle: stdoutPipe.fileHandleForReading)
        let stderrReader = PipeLineReader(fileHandle: stderrPipe.fileHandleForReading)

        stdoutReader.onLine = { [weak self] line in
            DispatchQueue.main.async {
                self?.handleStandardOutputLine(line, sessionID: sessionID)
            }
        }
        stderrReader.onLine = { [weak self] line in
            DispatchQueue.main.async {
                self?.handleStandardErrorLine(line, sessionID: sessionID)
            }
        }
        process.terminationHandler = { [weak self] terminatedProcess in
            DispatchQueue.main.async {
                self?.handleTermination(of: sessionID, process: terminatedProcess)
            }
        }

        runningSessions[sessionID] = RunningSession(
            projectID: project.id,
            process: process,
            stdoutReader: stdoutReader,
            stderrReader: stderrReader,
            rootURL: rootURL,
            securityScopeActive: securityScopeActive,
            onEvent: onEvent
        )
        activeProjectIDs.insert(project.id)
        onEvent(.status(.launching))

        do {
            try process.run()
            stdoutReader.start()
            stderrReader.start()
        } catch {
            finishFailedLaunch(
                sessionID: sessionID,
                summary: "LiquidCoder failed to launch `codex`: \(error.localizedDescription)"
            )
        }
    }

    private func handleStandardOutputLine(_ line: String, sessionID: CodexSession.ID) {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String,
            var runningSession = runningSessions[sessionID]
        else {
            return
        }

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
            runningSession.didCompleteTurn = true
            runningSession.onEvent(.status(.completed))
        default:
            break
        }

        runningSessions[sessionID] = runningSession
    }

    private func handleStandardErrorLine(_ line: String, sessionID: CodexSession.ID) {
        guard var runningSession = runningSessions[sessionID] else {
            return
        }

        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        runningSession.stderrLines.append(trimmed)
        if runningSession.stderrLines.count > 40 {
            runningSession.stderrLines.removeFirst(runningSession.stderrLines.count - 40)
        }

        runningSessions[sessionID] = runningSession
    }

    private func handleTermination(of sessionID: CodexSession.ID, process: Process) {
        guard let runningSession = runningSessions.removeValue(forKey: sessionID) else {
            return
        }

        runningSession.stdoutReader.stop()
        runningSession.stderrReader.stop()

        if runningSession.securityScopeActive {
            runningSession.rootURL.stopAccessingSecurityScopedResource()
        }

        activeProjectIDs.remove(runningSession.projectID)

        guard process.terminationStatus == 0 else {
            let summary = runningSession.stderrLines.last
                ?? "Codex exited with status \(process.terminationStatus). LiquidCoder launched the process, but the CLI failed before completing the turn."
            runningSession.onEvent(.failed(summary))
            return
        }

        if !runningSession.didCompleteTurn {
            runningSession.onEvent(.status(.completed))
        }
    }

    private func finishFailedLaunch(sessionID: CodexSession.ID, summary: String) {
        guard let runningSession = runningSessions.removeValue(forKey: sessionID) else {
            return
        }

        runningSession.stdoutReader.stop()
        runningSession.stderrReader.stop()

        if runningSession.securityScopeActive {
            runningSession.rootURL.stopAccessingSecurityScopedResource()
        }

        activeProjectIDs.remove(runningSession.projectID)
        runningSession.onEvent(.failed(summary))
    }
}

private final class PipeLineReader {
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

            if let line = String(data: lineData, encoding: .utf8) {
                onLine?(line)
            }
        }
    }

    private func flushBuffer() {
        guard !buffer.isEmpty else {
            return
        }

        defer { buffer.removeAll(keepingCapacity: false) }

        if let line = String(data: buffer, encoding: .utf8) {
            onLine?(line)
        }
    }
}
