<div align="center">
  <h1> App Launcher </h1>

<div align="center">
  <h2> MainPage</h2>
  <img width="916" height="776" alt="image" src="https://github.com/user-attachments/assets/bc41eb74-5a40-4c52-be3d-99ddf1c6be0b" /> 
</div>


| Quick config | Launch param config |
| ----------- | ----------- |
| <img width="913" height="764" alt="image" src="https://github.com/user-attachments/assets/6ccf2a95-a33b-4c83-b419-d574d097a1ca" /> | <img width="914" height="769" alt="image" src="https://github.com/user-attachments/assets/be270c0a-8e87-45c3-acad-060befb591bc" /> |

| Stats for fun | Folder |
| ----------- | ----------- |
| <img width="914" height="765" alt="image" src="https://github.com/user-attachments/assets/99898318-d667-4f31-b7de-bd8c0e4d32d1" /> |<img width="911" height="760" alt="image" src="https://github.com/user-attachments/assets/9150baa0-337f-498d-97d6-646fdcdd9164" />  |


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
