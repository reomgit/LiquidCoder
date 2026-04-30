# LiquidCoder

LiquidCoder is a native macOS 26+ SwiftUI conductor for local Codex work: user-added projects in the sidebar, repeatable Codex sessions inside each project, chat on the main surface, and git/project actions close at hand.

The target borrows the useful Codex desktop app structure without copying it outright: project navigation, a chat/composer workspace, project context controls, commit controls, and quick access to the project root in Finder, Cursor, VS Code, or Ghostty. The strategic difference is orchestration: LiquidCoder should become the place where one user conducts multiple project-scoped Codex sessions without losing track of context, branches, or commits.

## Current State

- Native SwiftUI macOS app targeting macOS 26.2.
- Starts with no built-in projects.
- Users add local project folders through a directory picker.
- Project sidebar with recent sessions under each project.
- Liquid Glass chat workspace and composer.
- Commit / Commit & Push controls plus Finder, Cursor, VS Code, and Ghostty launch buttons.
- Product docs and agent instructions are in place.

This is not yet a functioning Codex process manager. The UI is the first vertical slice; the real value arrives when the app can launch a real `codex` process for the selected project, stream the transcript, and commit reviewed changes.

## Product Direction

LiquidCoder should become a local desktop control plane for Codex sessions:

- Let users add, select, and persist local project roots.
- Run multiple Codex sessions against separate projects or worktrees.
- Keep sessions grouped under their project in the sidebar.
- Show live transcripts, plans, command output, context usage, branch, and git state.
- Keep all project data local unless the user explicitly opts into external services.
- Provide review surfaces before changes are committed or pushed.
- Support future agent backends through a narrow adapter protocol rather than UI-specific integrations.

## Architecture Plan

1. **App Shell**
   - `ContentView.swift` owns state, project selection, and the native `NavigationSplitView`.
   - `SideView.swift` owns the native SwiftUI sidebar.
   - `ProjectChatView.swift` owns the project chat/detail surface.
   - `LiquidGlassComponents.swift` contains reusable Codex-style controls.
   - `WorkspaceModels.swift` holds temporary project/session data and the first domain vocabulary.

2. **Codex Runtime**
   - Add a `CodexProcessRunner` responsible for launching `codex` with a working directory, environment, approval policy, and model selection.
   - Stream stdout/stderr into a transcript model.
   - Record process lifecycle events separately from rendered UI text.

3. **Persistence**
   - Store workspaces, agents, transcripts, and settings locally.
   - Keep secrets out of project files.
   - Prefer simple file-backed JSON or SQLite before inventing a sync layer.

4. **Git Awareness**
   - Track branch, dirty files, staged files, commits, and diffs per agent.
   - Require explicit user action for destructive git operations.

5. **Backend Adapters**
   - Start with Codex.
   - Later add adapters for Claude Code or other CLIs only after Codex session management is stable.

## Development

Open the project in Xcode:

```sh
open LiquidCoder.xcodeproj
```

Build from the command line:

```sh
xcodebuild -scheme LiquidCoder -project LiquidCoder.xcodeproj build
```

## Immediate Next Work

1. Implement a real `CodexProcessRunner`.
2. Wire the composer to create a new session under the selected project.
3. Replace mocked session rows with streamed process output and persisted transcripts.
4. Replace plain path persistence with security-scoped bookmarks if sandboxing stays enabled.
5. Make the Commit control open a diff/review flow before writing git history.

## Hard Constraints

- Do not make this Electron.
- Do not hand-build a fake sidebar. Use the native SwiftUI sidebar/list APIs.
- Do not store user code or transcripts on a hosted service by default.
- Do not fake agent state in production UI.
- Do not couple the UI directly to one CLI command format.
- Do not drift back into a card dashboard; this is a project/session conductor.
- Do not add Claude Code support until Codex is boringly reliable.
