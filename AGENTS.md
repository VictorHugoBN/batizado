# Batizado

macOS menu bar app that keeps a MacBook awake with the lid closed by toggling `pmset disablesleep`, with a
user-level guardian that reverts it on low battery, thermal pressure or app death. Swift 6, SwiftUI, SwiftPM.
Open source (MIT), signed ad hoc, no Developer ID.

This file is the single source of instructions for coding agents. Keep it lean and self-contained. Do not add
a `CLAUDE.md` or `CLAUDE.local.md`: either one stops Claude Code from reading this file.

## Project Structure

- `Package.swift` — one package, five targets
- `Sources/BatizadoCore/` — pure logic shared by the app and the guardian (policies, state machine, text
  generators). No AppKit, IOKit, file I/O or process spawning here
- `Sources/BatizadoSystem/` — thin system adapters both executables need (shared state files in
  `~/Library/Application Support/Batizado/`, process identity, `SleepDisabled`). No decisions here
- `Sources/Batizado/` — the menu bar app (SwiftUI `MenuBarExtra`, window style)
- `Sources/BatizadoGuardian/` — the watchdog executable, shipped inside the app bundle
- `Tests/BatizadoCoreTests/` — unit tests for the core (Swift Testing)
- `scripts/bundle.sh` — assembles and ad-hoc signs `build/Batizado.app`
- `Makefile` — every workflow goes through it; run `make help`

## Core Rules (always apply)

- Code, comments, commits and UI strings in **English** (en-US).
- Never run anything as root and never add a root daemon. The only privileged surface is a `sudoers` rule
  allowing exactly `/usr/bin/pmset -a disablesleep 0` and `/usr/bin/pmset -a disablesleep 1`. Do not widen it.
- Never call `pmset` or `sudo` with strings built from input. Absolute path, fixed arguments.
- Do not use `SMAppService`. With ad-hoc signing the registration breaks on every rebuild; login items and
  the guardian are plain LaunchAgent plists in the user's `~/Library/LaunchAgents`.
- Decisions live in `BatizadoCore` as pure functions over state and events. The app and the guardian only
  translate system events in and execute effects out. If logic needs a test, it belongs in the core.
- The UI shows the real `SleepDisabled` value read from the system, never an assumed one.
- Do not copy code from other keep-awake apps. Code Awake, the behavioral reference, has no license.
- `BUNDLE_ID` in the Makefile and `AppInfo.bundleIdentifier` must stay identical.
- Never edit, stage or commit anything under `.claude/`, `.agents/`, `.superset/` or `plans/` into git; they
  are ignored on purpose.
- Never add co-author or AI trailers to commits.

## Conventions

- Commits: Conventional Commits (`feat:`, `fix:`, `refactor:`, `chore:`, `docs:`, `test:`), one logical
  change per commit. Stage specific files; never `git add -A`.
- Branches: until v1.0 the maintainer commits straight to `main`, one plan phase per commit. Contributions
  and everything after v1.0 use `type/slug` branches off `main`, merged through a pull request.
- `CHANGELOG.md`: one bullet per user-visible change under `[Unreleased]`, at most two lines, starting with
  Add, Change, Deprecate, Remove, Fix or Security.
- Comments: none by default. When one is needed, a single line explaining why, not what.
- Formatting is owned by `swift format` with the repo's `.swift-format`; do not hand-format against it.
- Tests exercise observable behavior through a module's public interface: given a state and an event, assert
  the new state and the effects. Do not assert call order or private details.

## Feedback Loops

Run these and read the real output before claiming anything works:

```sh
make check        # lint + release build + tests; must pass before every commit
make fmt          # fix formatting reported by lint
make run          # build the bundle and launch it from ./build
```

The build needs Xcode 27 with its license accepted. The Makefile exports `DEVELOPER_DIR` itself; do not run
`xcode-select -s`. With the Command Line Tools alone, `@State` and XCTest fail to compile.

Anything that touches the system (power assertions, `disablesleep`, the `sudoers` rule, LaunchAgents, screen
lock, notifications) cannot be unit tested. Verify it by hand and say exactly what you ran and saw:

```sh
pmset -g | grep SleepDisabled                                  # real state
pmset -g assertions | grep -i batizado                         # assertions held by the app
pmset -g log | grep -E "Clamshell|Entering Sleep|Wake from"    # did the Mac sleep with the lid closed?
```

"I could not test the lid" is an acceptable report. "It should work" is not.
