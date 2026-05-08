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

private typealias TerminalPaletteColor = SwiftTerm.Color

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

    func refreshAppearance() {
        applySystemTheme()
    }

    private func configureTerminalView() {
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        applySystemTheme()
        terminalView.getTerminal().setCursorStyle(.steadyBlock)
        terminalView.getTerminal().ansi256PaletteStrategy = .base16LabHarmonious
        terminalView.optionAsMetaKey = true
        terminalView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func applySystemTheme() {
        let background = NSColor.controlBackgroundColor
        let foreground = NSColor.labelColor

        terminalView.nativeBackgroundColor = background
        terminalView.nativeForegroundColor = foreground
        terminalView.installColors(Self.makeTerminalPalette(background: background, foreground: foreground))
        terminalView.caretColor = NSColor.controlAccentColor
    }

    private static func makeTerminalPalette(background: NSColor, foreground: NSColor) -> [TerminalPaletteColor] {
        let dimForeground = foreground.withSystemEffect(.disabled)
        let elevatedBackground = background.blended(withFraction: 0.16, of: foreground) ?? foreground

        return [
            terminalColor(background),
            terminalColor(NSColor.systemRed),
            terminalColor(NSColor.systemGreen),
            terminalColor(NSColor.systemYellow),
            terminalColor(NSColor.systemBlue),
            terminalColor(NSColor.systemPink),
            terminalColor(NSColor.systemTeal),
            terminalColor(dimForeground),
            terminalColor(elevatedBackground),
            terminalColor(NSColor.systemRed.highlight(withLevel: 0.18) ?? NSColor.systemRed),
            terminalColor(NSColor.systemGreen.highlight(withLevel: 0.18) ?? NSColor.systemGreen),
            terminalColor(NSColor.systemYellow.highlight(withLevel: 0.12) ?? NSColor.systemYellow),
            terminalColor(NSColor.systemBlue.highlight(withLevel: 0.16) ?? NSColor.systemBlue),
            terminalColor(NSColor.systemPink.highlight(withLevel: 0.14) ?? NSColor.systemPink),
            terminalColor(NSColor.systemTeal.highlight(withLevel: 0.14) ?? NSColor.systemTeal),
            terminalColor(foreground)
        ]
    }

    private static func terminalColor(_ color: NSColor) -> TerminalPaletteColor {
        let resolved = color.usingColorSpace(.sRGB) ?? color
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return TerminalPaletteColor(
            red: UInt16(max(0, min(65535, Int(red * 65535)))),
            green: UInt16(max(0, min(65535, Int(green * 65535)))),
            blue: UInt16(max(0, min(65535, Int(blue * 65535))))
        )
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
        controller.refreshAppearance()
        controller.ensureStarted()
    }
}

final class TerminalContainerView: NSView {
    private weak var hostedTerminal: NSView?
    private let contentInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

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
            terminalView.frame = NSRect(
                x: contentInsets.left,
                y: contentInsets.bottom,
                width: max(0, bounds.width - contentInsets.left - contentInsets.right),
                height: max(0, bounds.height - contentInsets.top - contentInsets.bottom)
            )
            hideTerminalScrollers(in: terminalView)
            return
        }

        terminalView.removeFromSuperview()
        hostedTerminal = terminalView
        addSubview(terminalView)

        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentInsets.left),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -contentInsets.right),
            terminalView.topAnchor.constraint(equalTo: topAnchor, constant: contentInsets.top),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -contentInsets.bottom)
        ])

        hideTerminalScrollers(in: terminalView)

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.window?.makeFirstResponder(terminalView)
        }
    }

    private func hideTerminalScrollers(in view: NSView) {
        if let scroller = view as? NSScroller {
            scroller.isHidden = true
            scroller.alphaValue = 0
            return
        }

        for subview in view.subviews {
            hideTerminalScrollers(in: subview)
        }
    }
}
