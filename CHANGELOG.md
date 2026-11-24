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
