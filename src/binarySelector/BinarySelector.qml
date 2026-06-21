import qs
import "../state"
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    Loader {
        id: binarySelectorLoader
        active: LauncherState.binarySelectorOpen

        sourceComponent: PanelWindow {
            id: panelWindow

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:binarySelector"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors.top: true
            margins {
                top: Config?.options.bar.vertical ? Appearance.sizes.hyprlandGapsOut : Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut
            }

            mask: Region {
                item: content
            }

            implicitHeight: 620
            implicitWidth: 1000

            Component.onCompleted: {
                GlobalFocusGrab.addDismissable(panelWindow);
            }
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    LauncherState.binarySelectorOpen = false;
                }
            }

            BinarySelectorContent {
                id: content
                anchors.fill: parent
            }
        }
    }

    function toggleBinarySelector() {
        LauncherState.binarySelectorOpen = !LauncherState.binarySelectorOpen
    }

    Connections {
        target: LauncherState
        function onAppLauncherOpenChanged() {
            if (!LauncherState.appLauncherOpen && LauncherState.binarySelectorOpen)
                LauncherState.binarySelectorOpen = false
        }
        // Lives in the persistent Scope (not the lazily-loaded content) so it
        // reliably clears the folder target once the picker closes — otherwise
        // a later IPC-driven open would inherit a stale folder id.
        function onBinarySelectorOpenChanged() {
            if (!LauncherState.binarySelectorOpen)
                LauncherState.binarySelectorTargetFolderId = ""
        }
    }

    IpcHandler {
        target: "binarySelector"

        function toggle(): void {
            root.toggleBinarySelector();
        }
        function open(): void {
            LauncherState.binarySelectorOpen = true;
        }
        function close(): void {
            LauncherState.binarySelectorOpen = false;
        }
    }
}
