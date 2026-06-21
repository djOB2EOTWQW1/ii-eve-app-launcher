# ii-eve-app-launcher

## Screenshot

| MainPage | Quick config |
| ----------- | ----------- |
| <img width="910" height="762" alt="image" src="https://github.com/user-attachments/assets/04c62a72-e3ca-442f-b70c-69637b4a0284" /> | <img width="903" height="751" alt="image" src="https://github.com/user-attachments/assets/6ca248f4-5143-44ad-8ff8-f288b890eaaa" /> |

| Launch param config | Folder |
| ----------- | ----------- |
| <img width="917" height="757" alt="image" src="https://github.com/user-attachments/assets/bcf3f580-ea72-40e5-8d29-61b18d0fff69" /> | <img width="956" height="795" alt="image" src="https://github.com/user-attachments/assets/1bc00815-8306-47d9-88fa-921c8a2cbb8b" /> |


Application launcher extension for [ii-eve](https://github.com/djOB2EOTWQW1/ii-eve) / [ii-vynx](https://github.com/vaguesyntax/ii-vynx) Quickshell shells. Extracted from the built-in ii-eve launcher.

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

  (Runtime binding via `hyprctl keyword bind` is not possible — Hyprland's non-legacy/lua
  config parser disables `hyprctl keyword` — so the config line above is the way to bind it.)

## License

GPL-3.0.
