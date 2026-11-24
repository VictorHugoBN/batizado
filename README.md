# Batizado

A macOS menu bar app that keeps your MacBook awake with the lid closed, so long-running coding agents keep
working while you check on them remotely.

> *Café batizado* is Brazilian for coffee "baptized" with a shot of something stronger.

**Status: pre-alpha.** The repository currently holds the project scaffold: the app shows a menu bar icon
with a Quit button and nothing else. The features below are the plan for v1, not what is shipped today.

## Why

Apps that promise a "closed lid" mode usually hold a `PreventSystemSleep` power assertion. macOS ignores that
assertion when the lid closes without an external display, so the Mac sleeps anyway. The setting that always
works is `pmset disablesleep 1`, which needs administrator rights and is dangerous on its own: the Mac stays
awake until the battery dies or it overheats in a bag, and the setting survives a reboot.

Batizado uses `disablesleep` and wraps it in safeguards.

## Planned for v1

- **Keep awake**: prevents idle sleep. No privileges, nothing installed.
- **Closed lid**: turns on `disablesleep`. Asks for your administrator password once, on first use.
- **Guardian**: a separate user-level process that turns `disablesleep` back off when the battery is low
  (20% by default), when the system reports serious thermal pressure, or when the app crashes or is killed.
- **Lock on lid close**: locks the screen when you close the lid, unless an external display is in use.
- **Auto turn off**: a timer with a five-minute warning and an extend action.
- The menu bar icon reflects the real `SleepDisabled` state read from the system.

## How the privilege works

Nothing in this project runs as root. On first use of *Closed lid*, the app installs a `sudoers` rule that
lets your user run exactly two commands without a password:

```
/usr/bin/pmset -a disablesleep 0
/usr/bin/pmset -a disablesleep 1
```

The rule is validated before it is installed and can be removed from the app's menu. The trade-off is that
any process running as your user can toggle `disablesleep`.

## Requirements

- Apple Silicon Mac, macOS 14 or later (developed and tested on macOS 27)
- Xcode 27 with its license accepted (`sudo xcodebuild -license accept`). The Makefile selects the Xcode
  toolchain by itself; you do not need to change `xcode-select`.

## Build from source

There are no prebuilt binaries: the app is signed ad hoc, without a Developer ID.

```sh
git clone https://github.com/VictorHugoBN/batizado.git
cd batizado
make install      # builds, signs ad hoc and copies Batizado.app to /Applications
```

Other targets:

```sh
make help         # list every target
make run          # build and launch from ./build
make check        # lint, build and test
make uninstall    # quit the app and remove it from /Applications
```

## Contributing

`AGENTS.md` describes the project layout, rules and feedback loops for both humans and coding agents. Run
`make setup` once to install the pre-commit hooks, and `make check` before every commit.

## Sponsor

If Batizado keeps your agents running, you can
[buy me a batizado coffee](https://github.com/sponsors/VictorHugoBN).

## License

[MIT](LICENSE)
