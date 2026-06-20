import QtQuick
import Quickshell
import "../appLauncher"
import "../binarySelector"

// Loaded as an extension "service" (instantiated at root scope by ExtensionServices),
// which lets it declare its own top-level windows. Hosts the app launcher and
// binary-selector LayerShell panels — each registers its own IpcHandler / GlobalShortcut.
//
// Opening is driven by the GlobalShortcut "quickshell:appLauncherToggle"; a key must be
// bound to it in the Hyprland config (ii-eve ships that bind; other shells add one line —
// see README). Runtime binding via `hyprctl keyword bind` isn't possible because the
// lua/hyprlang config parser disables `hyprctl keyword`.
Scope {
    id: root

    AppLauncher {}
    BinarySelector {}
}
