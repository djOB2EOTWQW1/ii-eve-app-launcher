import qs
import "../state"
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "LauncherKeys.js" as LK

Scope {
    id: root
    property bool detach: false

    // Toggling detach only makes sense while the launcher is actually open —
    // firing it from the closed state would just leave a hidden FloatingWindow
    // around and surprise the user the next time they open the launcher.
    function toggleDetach() {
        if (!LauncherState.appLauncherOpen) return
        root.detach = !root.detach
    }

    onDetachChanged: {
        if (root.detach) {
            if (launcherLoader.item) GlobalFocusGrab.removeDismissable(launcherLoader.item)
            launcherLoader.active = false
            detachedLoader.active = true
        } else {
            detachedLoader.active = false
            launcherLoader.active = true
        }
    }

    Loader {
        id: launcherLoader
        active: true

        sourceComponent: PanelWindow {
            id: panelWindow
            visible: LauncherState.appLauncherOpen

            function hide() {
                LauncherState.appLauncherOpen = false
            }

            exclusionMode: ExclusionMode.Normal
            WlrLayershell.namespace: "quickshell:appLauncher"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            mask: Region {
                item: launcherBackground
            }

            onVisibleChanged: {
                if (visible) {
                    GlobalFocusGrab.addDismissable(panelWindow)
                } else {
                    GlobalFocusGrab.removeDismissable(panelWindow)
                }
            }

            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    panelWindow.hide()
                }
            }

            StyledRectangularShadow {
                target: launcherBackground
                radius: launcherBackground.radius
            }

            Rectangle {
                id: launcherBackground
                focus: true
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

                readonly property bool fixedSize: (LauncherPersist?.windowSize ?? "settings") === "settings"
                anchors.centerIn: parent
                width: fixedSize ? 900 : (parent.width - 2 * Appearance.sizes.hyprlandGapsOut)
                height: fixedSize ? 750 : (parent.height - 2 * Appearance.sizes.hyprlandGapsOut)

                Behavior on width {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on height {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                LauncherContent {
                    id: launcherContent
                }

                Keys.onPressed: (event) => LK.handleKey(event, launcherContent, {
                    onEscapeDismissIfIdle: () => panelWindow.hide(),
                    onCloseSettings: () => launcherContent.closeSettings(),
                    onToggleDetach: () => root.toggleDetach(),
                    onToggleHelp: () => launcherContent.toggleHelp(),
                    onFocusSearch: () => launcherContent.focusSearch()
                })
            }
        }
    }

    Loader {
        id: detachedLoader
        active: false

        sourceComponent: FloatingWindow {
            id: detachedRoot
            color: "transparent"
            visible: LauncherState.appLauncherOpen

            readonly property bool fixedSize: (LauncherPersist?.windowSize ?? "settings") === "settings"
            width: fixedSize ? 900 : implicitWidth
            height: fixedSize ? 750 : implicitHeight

            StyledRectangularShadow {
                target: detachedBackground
                radius: detachedBackground.radius
            }

            Rectangle {
                id: detachedBackground
                focus: true
                anchors.fill: parent
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

                LauncherContent {
                    id: launcherContent
                }

                Keys.onPressed: (event) => LK.handleKey(event, launcherContent, {
                    onCloseSettings: () => launcherContent.closeSettings(),
                    onToggleDetach: () => root.toggleDetach(),
                    onToggleHelp: () => launcherContent.toggleHelp(),
                    onFocusSearch: () => launcherContent.focusSearch()
                })
            }
        }
    }

    IpcHandler {
        target: "appLauncher"

        function toggle(): void {
            LauncherState.appLauncherOpen = !LauncherState.appLauncherOpen
        }

        function close(): void {
            LauncherState.appLauncherOpen = false
        }

        function open(): void {
            LauncherState.appLauncherOpen = true
        }
    }

    GlobalShortcut {
        name: "appLauncherToggle"
        description: "Toggles app launcher on press"

        onPressed: {
            LauncherState.appLauncherOpen = !LauncherState.appLauncherOpen
        }
    }

    GlobalShortcut {
        name: "appLauncherToggleDetach"
        description: "Detach app launcher into a window / attach it back"

        onPressed: {
            root.toggleDetach()
        }
    }
}
