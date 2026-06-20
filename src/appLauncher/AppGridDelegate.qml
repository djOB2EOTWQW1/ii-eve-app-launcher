import qs
import "../state"
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "vimium"
import QtQuick
import QtQuick.Layouts
import Quickshell

// Grid delegate for a single tile — either a folder (Android-16 style squircle
// with a 2x2 preview) or an application (launch on click; drag onto a folder;
// long-press to enter selection mode).
Item {
    id: delegateRoot

    required property var modelData
    required property int index

    // LauncherContent reference (hints, selection state, drag state, etc.).
    property var launcher
    // Rectangle the appTile reparents to while dragging so it floats above
    // sibling tiles during the drag gesture.
    property Item innerLayer

    signal openFolderRequested(var folder)
    signal contextMenuForAppRequested(int entryIndex, real launcherX, real launcherY)
    signal contextMenuForFolderRequested(string folderId, real launcherX, real launcherY)

    readonly property bool isFolder: !!delegateRoot.modelData?.appIndices
    readonly property int entryIndex: delegateRoot.modelData?._originalIndex ?? -1
    readonly property string folderId: delegateRoot.modelData?.id ?? ""
    readonly property bool isSelected: !delegateRoot.isFolder
        && (delegateRoot.launcher?.selectedAppIndices?.indexOf(delegateRoot.entryIndex) ?? -1) >= 0
    readonly property bool appRunning: {
        const _w = HyprlandData.windowList   // subscribe for reactivity
        return !delegateRoot.isFolder && !!delegateRoot.modelData?.path
            && CustomApps.isPathRunning(delegateRoot.modelData.path)
    }
    readonly property var folderPreviewIcons: delegateRoot.isFolder
        ? CustomApps.folderPreviewIcons(delegateRoot.modelData, 4)
        : []

    // Live reorder shift. While another tile is dragged toward a drop target,
    // every tile between the dragged source and the drop target slides one
    // grid cell toward the source so the user sees the layout update in real
    // time (Dock.DockFileButton uses the same idea, just in 1D).
    readonly property int _shiftedIndex: {
        const launcher = delegateRoot.launcher
        if (!launcher) return delegateRoot.index
        const dragIdx = launcher.draggedGridIndex
        const dropIdx = launcher.dropGridIndex
        if (dragIdx < 0 || dropIdx < 0 || dragIdx === dropIdx) return delegateRoot.index
        if (delegateRoot.index === dragIdx) return delegateRoot.index
        if (dragIdx < dropIdx && delegateRoot.index > dragIdx && delegateRoot.index <= dropIdx)
            return delegateRoot.index - 1
        if (dragIdx > dropIdx && delegateRoot.index >= dropIdx && delegateRoot.index < dragIdx)
            return delegateRoot.index + 1
        return delegateRoot.index
    }

    readonly property real _shiftDx: {
        const cols = delegateRoot.launcher?.gridColumns ?? 1
        const cellW = delegateRoot.launcher?.gridCellWidth ?? 0
        return ((delegateRoot._shiftedIndex % cols) - (delegateRoot.index % cols)) * cellW
    }

    readonly property real _shiftDy: {
        const cols = delegateRoot.launcher?.gridColumns ?? 1
        const cellH = delegateRoot.launcher?.gridCellHeight ?? 0
        return (Math.floor(delegateRoot._shiftedIndex / cols) - Math.floor(delegateRoot.index / cols)) * cellH
    }

    Timer {
        id: longPressTimer
        interval: 500
        repeat: false
        onTriggered: {
            delegateRoot.launcher.selectionModeActive = true
            delegateRoot.launcher.toggleAppSelection(delegateRoot.entryIndex)
            itemArea.longPressActivated = true
        }
    }

    // Visuals (and the MouseAreas that drag them) live inside this wrapper so
    // the live-shift Translate moves the visual but NOT the DropAreas declared
    // as siblings below. Putting the DropArea inside the translated subtree
    // would carry its hit zone along with the shift — the cursor would slide
    // out of the DropArea immediately, fire onExited, the shift would revert,
    // the cursor would re-enter, fire onEntered, and the cycle would oscillate
    // every frame (the bug fixed in this commit).
    Item {
        id: visualWrapper
        anchors.fill: parent

        transform: Translate {
            x: delegateRoot._shiftDx
            y: delegateRoot._shiftDy
            Behavior on x {
                enabled: !(delegateRoot.launcher?.suppressAnim ?? false)
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on y {
                enabled: !(delegateRoot.launcher?.suppressAnim ?? false)
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        VimiumTarget {
            x: 12
            y: 12
            registry: delegateRoot.launcher?.mainRegistry ?? null
            participates: delegateRoot.launcher
                ? !(delegateRoot.launcher.selectionModeActive && delegateRoot.isFolder)
                : true
            onActivated: {
                const l = delegateRoot.launcher
                if (!l) return
                if (delegateRoot.isFolder) {
                    if (l.selectionModeActive) return
                    delegateRoot.openFolderRequested(delegateRoot.modelData)
                    return
                }
                if (l.selectionModeActive) {
                    if (delegateRoot.entryIndex >= 0) l.toggleAppSelection(delegateRoot.entryIndex)
                    return
                }
                CustomApps.activate(delegateRoot.modelData)
                LauncherState.appLauncherOpen = false
            }
        }

    // Android 16 style folder tile: rounded-square preview container
    // with up to 4 mini app icons in a 2x2 grid.
    Rectangle {
        id: folderTileItem
        anchors.fill: parent
        anchors.margins: 6
        visible: delegateRoot.isFolder
        radius: Appearance.rounding.normal
        color: folderHoverArea.pressed
            ? Appearance.colors.colLayer3Active
            : folderHoverArea.containsMouse
                ? Appearance.colors.colLayer3
                : "transparent"

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Drag.active: folderHoverArea.drag.active && !(delegateRoot.launcher?.selectionModeActive ?? false)
        Drag.source: folderHoverArea
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2
        Drag.supportedActions: Qt.MoveAction

        states: State {
            name: "dragging"
            when: folderTileItem.Drag.active
            PropertyChanges {
                target: folderTileItem
                anchors.fill: undefined
                anchors.margins: 0
                opacity: 0.88
                scale: 1.04
                z: 50
            }
            ParentChange {
                target: folderTileItem
                parent: delegateRoot.innerLayer
            }
        }

        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: delegateRoot.isFolder
                && delegateRoot.launcher?.reorderTargetFolderId === delegateRoot.folderId
                && delegateRoot.launcher?.draggedFolderId !== delegateRoot.folderId
            color: Appearance.colors.colPrimaryContainer
            opacity: 0.35

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 6

            Rectangle {
                id: folderSquircle
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: delegateRoot.launcher?.iconSize ?? 64
                Layout.preferredHeight: delegateRoot.launcher?.iconSize ?? 64
                radius: (delegateRoot.launcher?.iconSize ?? 64) * 0.28
                color: delegateRoot.launcher?.hoverFolderId === delegateRoot.folderId
                        && (delegateRoot.launcher?.draggedEntryIndex ?? -1) >= 0
                    ? Appearance.colors.colPrimaryContainer
                    : Appearance.m3colors.m3surfaceContainerHigh
                border.width: delegateRoot.launcher?.hoverFolderId === delegateRoot.folderId
                        && (delegateRoot.launcher?.draggedEntryIndex ?? -1) >= 0 ? 2 : 0
                border.color: Appearance.colors.colPrimary

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                Behavior on border.color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                FolderPreviewGrid {
                    anchors.centerIn: parent
                    width: parent.width * 0.72
                    height: parent.height * 0.72
                    icons: delegateRoot.folderPreviewIcons
                }

                MaterialSymbol {
                    visible: (delegateRoot.modelData?.appIndices?.length ?? 0) === 0
                    anchors.centerIn: parent
                    text: "folder"
                    iconSize: Math.round((delegateRoot.launcher?.iconSize ?? 64) * 0.5)
                    color: Appearance.colors.colOnLayer1
                }
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                text: delegateRoot.modelData?.name ?? ""
            }
        }

        MouseArea {
            id: folderHoverArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            drag.target: (delegateRoot.launcher?.selectionModeActive ?? false) ? null : folderTileItem
            drag.threshold: 8
            preventStealing: true

            onPressed: (mouse) => {
                if (mouse.button === Qt.LeftButton) {
                    delegateRoot.launcher.draggedFolderId = delegateRoot.folderId
                }
            }
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    const pos = folderHoverArea.mapToItem(delegateRoot.launcher, mouse.x, mouse.y)
                    delegateRoot.contextMenuForFolderRequested(delegateRoot.folderId, pos.x, pos.y)
                    return
                }
                if (folderTileItem.Drag.active) return
                delegateRoot.openFolderRequested(delegateRoot.modelData)
            }
            onReleased: {
                const launcher = delegateRoot.launcher
                const reorderTargetId = launcher.reorderTargetFolderId
                const sourceId = delegateRoot.folderId
                launcher.suppressAnim = true
                launcher.draggedFolderId = ""
                launcher.reorderTargetFolderId = ""
                if (reorderTargetId.length > 0 && reorderTargetId !== sourceId) {
                    const fromIdx = CustomApps._folderIndexOfId(sourceId)
                    const toIdx = CustomApps._folderIndexOfId(reorderTargetId)
                    if (fromIdx >= 0 && toIdx >= 0) {
                        CustomApps.moveFolder(fromIdx, toIdx)
                    }
                }
                Qt.callLater(() => launcher.suppressAnim = false)
            }
            onCanceled: {
                const launcher = delegateRoot.launcher
                launcher.suppressAnim = true
                launcher.draggedFolderId = ""
                launcher.reorderTargetFolderId = ""
                Qt.callLater(() => launcher.suppressAnim = false)
            }
        }
    }

    Rectangle {
        id: appTile
        anchors.fill: parent
        anchors.margins: 6
        visible: !delegateRoot.isFolder
        radius: Appearance.rounding.normal
        color: itemArea.pressed
            ? Appearance.colors.colLayer3Active
            : itemArea.containsMouse
                ? Appearance.colors.colLayer3
                : "transparent"

        Drag.active: itemArea.drag.active && !(delegateRoot.launcher?.selectionModeActive ?? false)
        Drag.source: itemArea
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2
        Drag.supportedActions: Qt.MoveAction

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        states: State {
            name: "dragging"
            when: appTile.Drag.active
            PropertyChanges {
                target: appTile
                anchors.fill: undefined
                anchors.margins: 0
                opacity: 0.88
                scale: 1.04
                z: 50
            }
            ParentChange {
                target: appTile
                parent: delegateRoot.innerLayer
            }
        }

        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: delegateRoot.isSelected
            color: Appearance.colors.colPrimary
            opacity: 0.15
            z: 1
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: delegateRoot.isSelected
            color: "transparent"
            border.width: 2
            border.color: Appearance.colors.colPrimary
            z: 2
        }

        Rectangle {
            visible: delegateRoot.isSelected
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 6
            anchors.rightMargin: 6
            width: 20
            height: 20
            radius: 10
            color: Appearance.colors.colPrimary
            z: 3

            MaterialSymbol {
                anchors.centerIn: parent
                text: "check"
                iconSize: 13
                color: Appearance.colors.colOnPrimary
            }
        }

        Rectangle {
            visible: delegateRoot.appRunning && !delegateRoot.isSelected
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 5
            implicitWidth: 6
            implicitHeight: 6
            radius: height / 2
            color: Appearance.colors.colPrimary
            z: 3
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: !delegateRoot.isFolder
                && delegateRoot.launcher?.reorderTargetEntryIndex === delegateRoot.entryIndex
                && delegateRoot.launcher?.draggedEntryIndex !== delegateRoot.entryIndex
            color: Appearance.colors.colPrimaryContainer
            opacity: 0.35

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            Image {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: delegateRoot.launcher?.iconSize ?? 64
                Layout.preferredHeight: delegateRoot.launcher?.iconSize ?? 64
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                source: {
                    const icon = delegateRoot.modelData?.icon || ""
                    if (icon.startsWith("/")) return "file://" + icon
                    return Quickshell.iconPath(icon, "application-x-executable")
                }
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                text: delegateRoot.modelData?.name ?? ""
            }
        }

        MouseArea {
            id: itemArea
            // Exposed so DropArea sees it via drag.source during drag.
            property int entryIndex: delegateRoot.entryIndex
            property bool longPressActivated: false
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            drag.target: (delegateRoot.launcher?.selectionModeActive ?? false) ? null : appTile
            drag.threshold: 8
            preventStealing: true

            onPressed: (mouse) => {
                if (mouse.button === Qt.LeftButton) {
                    longPressActivated = false
                    delegateRoot.launcher.draggedEntryIndex = delegateRoot.entryIndex
                    if (!delegateRoot.launcher.selectionModeActive) {
                        longPressTimer.start()
                    }
                }
            }
            onPositionChanged: {
                if (drag.active && longPressTimer.running) {
                    longPressTimer.stop()
                }
            }
            onClicked: (mouse) => {
                if (longPressActivated) {
                    longPressActivated = false
                    return
                }
                if (mouse.button === Qt.RightButton) {
                    const pos = itemArea.mapToItem(delegateRoot.launcher, mouse.x, mouse.y)
                    delegateRoot.contextMenuForAppRequested(delegateRoot.entryIndex, pos.x, pos.y)
                    return
                }
                if (delegateRoot.launcher.selectionModeActive) {
                    delegateRoot.launcher.toggleAppSelection(delegateRoot.entryIndex)
                    return
                }
                if (!appTile.Drag.active) {
                    CustomApps.activate(delegateRoot.modelData)
                    LauncherState.appLauncherOpen = false
                }
            }
            onReleased: {
                longPressTimer.stop()
                const launcher = delegateRoot.launcher
                const targetFolder = launcher.hoverFolderId
                const reorderTarget = launcher.reorderTargetEntryIndex
                const idx = delegateRoot.entryIndex
                const inSelection = launcher.selectionModeActive
                launcher.suppressAnim = true
                launcher.hoverFolderId = ""
                launcher.draggedEntryIndex = -1
                launcher.reorderTargetEntryIndex = -1
                if (!inSelection && idx >= 0) {
                    if (targetFolder.length > 0) {
                        CustomApps.addAppToFolder(targetFolder, idx)
                    } else if (reorderTarget >= 0 && reorderTarget !== idx) {
                        CustomApps.moveAppInEntries(idx, reorderTarget)
                    }
                }
                Qt.callLater(() => launcher.suppressAnim = false)
            }
            onCanceled: {
                longPressTimer.stop()
                const launcher = delegateRoot.launcher
                launcher.suppressAnim = true
                launcher.hoverFolderId = ""
                launcher.draggedEntryIndex = -1
                launcher.reorderTargetEntryIndex = -1
                Qt.callLater(() => launcher.suppressAnim = false)
            }
        }

    }
    } // visualWrapper

    // Drop targets sit OUTSIDE visualWrapper so the live-shift Translate does
    // not move the hit zone with the visual. Their `enabled` clauses gate them
    // by tile kind so each delegate exposes only the drop logic that matches
    // the visible tile.

    // Folder drop target. Accepts both folder-reorder drags (sets
    // reorderTargetFolderId) and app-into-folder drags (sets hoverFolderId).
    // Splitting these into two stacked DropAreas would let the topmost one
    // swallow the event without accepting it, so this handles both cases.
    DropArea {
        id: folderDropArea
        anchors.fill: parent
        enabled: delegateRoot.isFolder && !folderTileItem.Drag.active
        onEntered: (drag) => {
            const launcher = delegateRoot.launcher
            if (!launcher) return
            const draggingFolder = (launcher.draggedFolderId ?? "") !== ""
            const draggingApp = (launcher.draggedEntryIndex ?? -1) >= 0
            if (draggingFolder) {
                if (launcher.draggedFolderId === delegateRoot.folderId) return
                launcher.reorderTargetFolderId = delegateRoot.folderId
                drag.accept(Qt.MoveAction)
            } else if (draggingApp) {
                launcher.hoverFolderId = delegateRoot.folderId
                drag.accept(Qt.MoveAction)
            }
        }
        onExited: {
            const launcher = delegateRoot.launcher
            if (!launcher) return
            if (launcher.reorderTargetFolderId === delegateRoot.folderId) {
                launcher.reorderTargetFolderId = ""
            }
            if (launcher.hoverFolderId === delegateRoot.folderId) {
                launcher.hoverFolderId = ""
            }
        }
    }

    // App reorder drop target.
    DropArea {
        id: reorderDropArea
        anchors.fill: parent
        enabled: !delegateRoot.isFolder && !appTile.Drag.active
        onEntered: (drag) => {
            const launcher = delegateRoot.launcher
            if (!launcher) return
            if ((launcher.draggedEntryIndex ?? -1) < 0) return     // not dragging an app
            if ((launcher.draggedFolderId ?? "") !== "") return   // dragging a folder
            if (launcher.draggedEntryIndex === delegateRoot.entryIndex) return  // onto itself
            launcher.reorderTargetEntryIndex = delegateRoot.entryIndex
            drag.accept(Qt.MoveAction)
        }
        onExited: {
            const launcher = delegateRoot.launcher
            if (launcher && launcher.reorderTargetEntryIndex === delegateRoot.entryIndex) {
                launcher.reorderTargetEntryIndex = -1
            }
        }
    }
}
