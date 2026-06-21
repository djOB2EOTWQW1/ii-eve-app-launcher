import QtQuick
import Quickshell
import Quickshell.Io
import "../appLauncher"
import "../binarySelector"

// Loaded as an extension "service" (instantiated at root scope by ExtensionServices),
// which lets it declare its own top-level windows. Hosts the app launcher and
// binary-selector LayerShell panels — each registers its own IpcHandler / GlobalShortcut.
//
// ExtensionServices also runs in auxiliary Quickshell processes — notably the settings app
// (`qs -p settings.qml`), which imports qs.services and so loads every extension service.
// Without a guard that second instance registers a duplicate "appLauncherToggle"
// GlobalShortcut + launcher window, so Super+Space fires in both processes and the
// launcher flickers/re-opens. Only the main shell process (`qs -c <name>`) should own the
// windows; we detect it from this process's own command line.
//
// Opening is driven by the GlobalShortcut "quickshell:appLauncherToggle"; a key must be
// bound to it in the Hyprland config (ii-eve ships that bind; other shells add one line —
// see README).
Scope {
    id: root

    property int _kind: 0 // 0 = undetermined, 1 = main shell, -1 = auxiliary process
    readonly property bool isMainShell: root._kind === 1

    Process {
        running: true
        command: ["bash", "-c", "tr '\\0' ' ' < /proc/" + Quickshell.processId + "/cmdline"]
        stdout: StdioCollector { id: cmdlineCollector }
        onExited: {
            // Main shell is launched as `qs -c <name>`; the settings app and other helpers
            // use `qs -p <file>`. Only the `-c` instance owns the launcher.
            root._kind = (/ -c /.test(String(cmdlineCollector.text || ""))) ? 1 : -1
        }
    }

    Loader {
        active: root.isMainShell
        sourceComponent: Component { AppLauncher {} }
    }

    Loader {
        active: root.isMainShell
        sourceComponent: Component { BinarySelector {} }
    }
}
