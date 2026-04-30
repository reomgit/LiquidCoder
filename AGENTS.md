# AGENTS.md

## Mission

You are building LiquidCoder: a native macOS 26+ SwiftUI conductor for project-scoped Codex sessions.

Your job is not to make a pretty dashboard and call it an IDE. Your job is to turn this into a reliable local control plane for real Codex work: project selection, new session launch, transcript visibility, git awareness, context tracking, and safe commit paths.

## Product Stance

- Codex compatibility comes first.
- Claude Code and other agent backends are future adapters, not current distractions.
- Local-first is a product requirement, not a slogan.
- The UI should use the useful Codex desktop app pattern without becoming a literal clone: user-added projects and sessions on the left, chat/composer on the right, commit and project actions near the top.
- This is a conductor app: the user chooses a project, starts sessions, reviews changes, and commits from one place.
- Use Liquid Glass intentionally for the sidebar, chat surface, and composer. Do not drift into generic decorative cards.

## Technical Direction

- Use SwiftUI for the app shell and native macOS 26 Liquid Glass APIs where available.
- Use `NavigationSplitView` and native `List` sidebar behavior for the app frame.
- Use AppKit bridges only when SwiftUI cannot express the required native behavior.
- Keep process execution isolated behind a dedicated runtime layer.
- Model project and session lifecycle explicitly: created, launching, running, waiting, blocked, completed, failed, cancelled.
- Keep transcript events structured. Rendered terminal text is a view of the data, not the source of truth.
- Keep git operations explicit and reviewable.

## Near-Term Priorities

1. Build the Codex process runner.
2. Wire the composer to launch a new Codex session in the selected project root.
3. Stream session output into structured transcript storage.
4. Replace plain path persistence with security-scoped bookmarks if sandboxing stays enabled.
5. Add git diff and review views before supporting destructive operations.

## Non-Negotiables

- Do not fake completed functionality in product copy or UI state.
- Do not introduce cloud storage or telemetry without explicit user control.
- Do not hard-code one user's filesystem paths into reusable code.
- Do not ship built-in sample projects. Projects must be user-added.
- Do not build custom Electron-looking sidebars; keep the sidebar native.
- Do not let multiple sessions mutate the same worktree without surfacing collision risk.
- Do not hide process errors behind generic "failed" labels.
- Do not add broad abstractions before one real Codex workflow works end to end.

## Code Style

- Prefer small SwiftUI views with clear data inputs.
- Prefer domain names that match the product: project, session, transcript, approval, branch, commit, diff.
- Keep comments rare and useful.
- Keep visual components reusable but not over-generalized.
- Verify with `xcodebuild -scheme LiquidCoder -project LiquidCoder.xcodeproj build` before claiming the app builds.
