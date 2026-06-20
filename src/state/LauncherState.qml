pragma Singleton
import QtQuick
import Quickshell

// Open-state for the launcher / binary-selector panels. The upstream ii-eve shell keeps
// these on GlobalStates; bundling them here makes the extension self-contained and lets it
// run on shells (e.g. ii-vynx) whose GlobalStates lacks them.
Singleton {
    id: root
    property bool appLauncherOpen: false
    property bool binarySelectorOpen: false
    property string binarySelectorTargetFolderId: ""
}
