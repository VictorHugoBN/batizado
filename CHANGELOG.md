# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/). The version matches the app's
`CFBundleShortVersionString`.

Each entry starts with one of: Add, Change, Deprecate, Remove, Fix, Security.

## [Unreleased]

- Add the repository scaffold: SwiftPM package (core library, menu bar app, guardian), Makefile,
  bundle script with ad-hoc signing, and a placeholder menu bar icon with a Quit button.
- Add the Keep awake and Keep display on toggles, backed by power assertions and restored on the next
  launch.
- Add a read-only Closed lid row and a three-state menu bar icon (off, awake, closed lid) that follow
  the system's real SleepDisabled value as it changes.
- Add the Closed lid toggle: a one-time helper rule (installed with the administrator password) lets the
  app toggle `disablesleep`; mismatches, a removed rule and Quit are handled, plus "Remove helper rule".
- Add the guardian LaunchAgent: it turns Closed lid off when the app crashes or is force quit, and the app
  shows why on the next launch and turns Closed lid back on.
- Add "Lock on lid close" (on by default): with Closed lid on, closing the lid without an external display
  locks the screen.
- Add the low battery protection: on battery at or below the "Low battery cutoff" (20% by default, 5% to
  50%), the guardian turns Closed lid and Keep awake off and the app notifies and shows why.
- Add the thermal protection: when macOS reports a serious or critical thermal state, the guardian turns
  Closed lid and Keep awake off and the app notifies; Closed lid stays off while the Mac is that hot.
- Add "Auto turn off" (Never, 1, 2, 4 or 8 hours): a countdown in the popover, a warning five minutes
  before with "Extend 30 min", and a deadline that survives a restart; the end turns everything off.
- Add "Launch at login": a plain agent in `~/Library/LaunchAgents` opens the app once at login, follows the
  app when it moves, and is removed when the toggle goes off.
- Change the launch restore: Keep awake and Closed lid come back after Quit, a crash or a restart, but not
  after a protection, the timer or turning them off; a restore that cannot run says why.
