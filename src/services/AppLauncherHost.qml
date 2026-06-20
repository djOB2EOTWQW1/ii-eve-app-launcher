import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services
import "../appLauncher"
import "../binarySelector"

// Loaded as an extension "service" (instantiated at root scope by ExtensionServices),
// which lets it declare its own top-level windows. Hosts the app launcher and
// binary-selector LayerShell panels — each registers its own IpcHandler / GlobalShortcut.
//
// The launcher's GlobalShortcut ("quickshell:appLauncherToggle") only fires if Hyprland
// has a matching `bind ... global, ...`. ii-eve ships that bind in its hyprland config,
// but other shells (ii-vynx) do not — so we register it at runtime with `hyprctl keyword
// bind` and re-apply it whenever Hyprland reloads its config (which would otherwise drop
// the runtime bind). The key combo is configurable via the extension's "hotkey" setting.
Scope {
    id: root
    property string extensionId: ""

    readonly property string hotkey: ExtensionManager.getExtensionConfig(root.extensionId, "hotkey", "SUPER,SPACE")

    function _applyBind() {
        if (!root.hotkey || root.hotkey.length === 0) return
        Quickshell.execDetached(["hyprctl", "keyword", "bind",
            `${root.hotkey},global,quickshell:appLauncherToggle`])
    }

    onExtensionIdChanged: root._applyBind()
    Component.onCompleted: root._applyBind()

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") root._applyBind()
        }
    }

    AppLauncher {}
    BinarySelector {}
}
