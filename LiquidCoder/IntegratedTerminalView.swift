//
//  IntegratedTerminalView.swift
//  LiquidCoder
//
//  Created by OpenAI Codex on 2026/04/30.
//

import AppKit
import Combine
import SwiftTerm
import SwiftUI

@MainActor
final class SessionTerminalStore: ObservableObject {
    private var controllers: [TerminalControllerKey: SessionTerminalController] = [:]

    func controller(
        for sessionID: CodexSession.ID,
        project: CodexProject,
        workspace: CodexWorkspace?
    ) -> SessionTerminalController {
        let rootURL = project.resolvedRootURL
        let workingDirectory = workspace?.worktreePath ?? rootURL.path
        let key = TerminalControllerKey(sessionID: sessionID, workingDirectory: workingDirectory)

        if let existing = controllers[key] {
            return existing
        }

        let controller = SessionTerminalController(
            projectRootURL: rootURL,
            workingDirectory: workingDirectory
        )
        controllers[key] = controller
        return controller
    }

}

private struct TerminalControllerKey: Hashable {
    let sessionID: CodexSession.ID
    let workingDirectory: String
}

@MainActor
final class SessionTerminalController: NSObject, ObservableObject, LocalProcessTerminalViewDelegate {
    @Published private(set) var currentDirectory: String?
    @Published private(set) var terminalTitle = "Shell"
    @Published private(set) var isRunning = false
    @Published private(set) var lastExitCode: Int32?

    let terminalView: LocalProcessTerminalView
    let workingDirectory: String

    private let projectRootURL: URL
    private var securityScopeActive = false

    init(projectRootURL: URL, workingDirectory: String) {
        self.projectRootURL = projectRootURL
        self.workingDirectory = workingDirectory
        self.terminalView = LocalProcessTerminalView(frame: .zero)
        super.init()
        configureTerminalView()
    }

    func ensureStarted() {
        guard !isRunning else {
            return
        }

        terminalView.getTerminal().resetToInitialState()
        terminalView.processDelegate = self

        securityScopeActive = projectRootURL.startAccessingSecurityScopedResource()
        let shellLaunch = Self.shellLaunchConfiguration(workingDirectory: workingDirectory)
        terminalView.startProcess(
            executable: shellLaunch.executable,
            args: shellLaunch.arguments,
            environment: shellLaunch.environment,
            execName: shellLaunch.execName,
            currentDirectory: workingDirectory
        )

        currentDirectory = workingDirectory
        terminalTitle = URL(fileURLWithPath: workingDirectory).lastPathComponent
        lastExitCode = nil
        isRunning = terminalView.process.running
    }

    func relaunch() {
        guard !isRunning else {
            return
        }

        ensureStarted()
    }

    func terminate() {
        guard terminalView.process.running else {
            releaseSecurityScope()
            return
        }

        terminalView.terminate()
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        terminalTitle = title.isEmpty ? "Shell" : title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, let url = URL(string: directory) else {
            return
        }

        currentDirectory = url.path
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        isRunning = false
        lastExitCode = exitCode
        releaseSecurityScope()
    }

    private func configureTerminalView() {
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        terminalView.nativeBackgroundColor = NSColor(
            calibratedRed: 0.08,
            green: 0.09,
            blue: 0.11,
            alpha: 1
        )
        terminalView.nativeForegroundColor = NSColor(
            calibratedRed: 0.88,
            green: 0.90,
            blue: 0.93,
            alpha: 1
        )
        terminalView.caretColor = NSColor.systemMint
        terminalView.getTerminal().setCursorStyle(.steadyBlock)
        terminalView.optionAsMetaKey = true
        terminalView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func releaseSecurityScope() {
        guard securityScopeActive else {
            return
        }

        projectRootURL.stopAccessingSecurityScopedResource()
        securityScopeActive = false
    }

    private static func shellLaunchConfiguration(workingDirectory: String) -> ShellLaunchConfiguration {
        let shell = userShellPath()
        let shellName = URL(fileURLWithPath: shell).lastPathComponent

        switch shellName {
        case "zsh", "bash", "sh", "ksh":
            return ShellLaunchConfiguration(
                executable: shell,
                arguments: ["-il"],
                execName: nil,
                environment: shellEnvironment(shell: shell, workingDirectory: workingDirectory)
            )
        case "fish":
            return ShellLaunchConfiguration(
                executable: shell,
                arguments: ["-l"],
                execName: nil,
                environment: shellEnvironment(shell: shell, workingDirectory: workingDirectory)
            )
        default:
            return ShellLaunchConfiguration(
                executable: shell,
                arguments: [],
                execName: "-" + shellName,
                environment: shellEnvironment(shell: shell, workingDirectory: workingDirectory)
            )
        }
    }

    private static func userShellPath() -> String {
        let environmentShell = ProcessInfo.processInfo.environment["SHELL"]
        if let environmentShell, FileManager.default.isExecutableFile(atPath: environmentShell) {
            return environmentShell
        }

        let bufferSize = sysconf(_SC_GETPW_R_SIZE_MAX)
        guard bufferSize > 0 else {
            return "/bin/zsh"
        }

        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var password = passwd()
        let resultPointer = UnsafeMutablePointer<UnsafeMutablePointer<passwd>?>.allocate(capacity: 1)
        defer { resultPointer.deallocate() }

        guard getpwuid_r(getuid(), &password, buffer, bufferSize, resultPointer) == 0 else {
            return "/bin/zsh"
        }

        guard let resolved = resultPointer.pointee else {
            return "/bin/zsh"
        }

        let shell = String(cString: resolved.pointee.pw_shell)
        return FileManager.default.isExecutableFile(atPath: shell) ? shell : "/bin/zsh"
    }

    private static func shellEnvironment(shell: String, workingDirectory: String) -> [String] {
        let processEnvironment = ProcessInfo.processInfo.environment
        var environment: [String: String] = [:]

        environment["HOME"] = processEnvironment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        environment["USER"] = processEnvironment["USER"] ?? NSUserName()
        environment["LOGNAME"] = processEnvironment["LOGNAME"] ?? environment["USER"]
        environment["SHELL"] = shell
        environment["PATH"] = processEnvironment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "LiquidCoder"
        environment["TERM_PROGRAM_VERSION"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        environment["PWD"] = workingDirectory

        for key in [
            "TMPDIR",
            "LANG",
            "LC_ALL",
            "LC_CTYPE",
            "__CF_USER_TEXT_ENCODING",
            "SSH_AUTH_SOCK"
        ] {
            if let value = processEnvironment[key], !value.isEmpty {
                environment[key] = value
            }
        }

        return environment.map { "\($0.key)=\($0.value)" }
    }
}

private struct ShellLaunchConfiguration {
    let executable: String
    let arguments: [String]
    let execName: String?
    let environment: [String]
}

struct IntegratedTerminalView: NSViewRepresentable {
    @ObservedObject var controller: SessionTerminalController

    func makeNSView(context: Context) -> TerminalContainerView {
        let container = TerminalContainerView()
        container.attach(controller.terminalView)
        controller.ensureStarted()
        return container
    }

    func updateNSView(_ nsView: TerminalContainerView, context: Context) {
        nsView.attach(controller.terminalView)
        controller.ensureStarted()
    }
}

final class TerminalContainerView: NSView {
    private weak var hostedTerminal: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(_ terminalView: NSView) {
        guard hostedTerminal !== terminalView else {
            terminalView.frame = bounds
            return
        }

        terminalView.removeFromSuperview()
        hostedTerminal = terminalView
        addSubview(terminalView)

        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.window?.makeFirstResponder(terminalView)
        }
    }
}
