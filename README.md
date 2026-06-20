# ii-eve-app-launcher

Application launcher extension for [ii-eve](https://github.com/djOB2EOTWQW1) / [ii-vynx](https://github.com/) Quickshell shells. Extracted from the built-in ii-eve launcher.

Provides:
- App launcher panel (grid, folders, recents, vimium-style keyboard navigation).
- Binary selector (add arbitrary executables as launchable entries, with extracted icons).

## How it works

The extension contributes a single **service** (`appLauncherHost`) which hosts the
launcher and binary-selector LayerShell windows. Shared state (`LauncherState`) and the
`CustomApps` logic are bundled as singletons, so the extension is self-contained and runs
on shells that lack the upstream ii-eve pieces.

## Keybind

The launcher opens via the Quickshell global shortcut `quickshell:appLauncherToggle`
(plus IPC: `qs -c ii ipc call appLauncher toggle`). A key must be bound to that shortcut
in your Hyprland config.

- **ii-eve**: already bound to `SUPER + SPACE` in the shipped keybinds — works out of the box.
- **other shells (e.g. ii-vynx)**: add one line to your lua keybinds
  (e.g. `~/.config/hypr/custom/keybinds.lua`):

  ```lua
  hl.bind("SUPER + SPACE", hl.dsp.global("quickshell:appLauncherToggle"), { description = "Shell: Toggle app launcher" })
  ```

  (Runtime binding via `hyprctl keyword bind` is attempted as a best-effort fallback, but
  Hyprland's non-legacy/lua config parser disables `hyprctl keyword`, so the config line
  above is the reliable method.)

## Config

- `hotkey` — key combo used by the best-effort runtime bind (default `SUPER,SPACE`,
  `hyprctl` bind syntax). Has no effect under the lua parser; bind in config instead.

## License

GPL-3.0.
