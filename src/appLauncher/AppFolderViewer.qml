import qs
import "../state"
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../common"
import "vimium"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

// Android 16 style expanded folder: dimmed backdrop + centered app grid panel.
Item {
    id: root
    property var folder: null
    property int iconSize: 64
    property var registry: null
    // LauncherContent root + its shared top layer. Set so a folder-app drag can
    // float over the whole launcher (not just the panel) and feed the launcher's
    // drag state, enabling drag between folders / out to the root grid.
    property var launcher: null
    property Item innerLayer: null
    signal closed()
    signal renameAppRequested(int appIndex, string currentName)
    // Right-click on empty space inside the folder panel. Coordinates are in
    // `root`'s item space; LauncherContent uses them to position its
    // launcher-wide AppContextMenu (so the user can add apps to the open folder
    // without having to close it first).
    signal emptyAreaRightClicked(real x, real y)

    property bool selectionModeActive: false
    property var selectedAppIndices: []

    // True while a folder-app drag is hovering over the panel itself — gates
    // the launcher's "eject to root" drop so dropping inside the panel never
    // ejects.
    property bool overPanel: false

    // Folder-scoped search query (#4). Filters this folder's apps only.
    property string searchText: ""

    // Panel size. Bound to a sensible default; the corner resize grip assigns
    // these directly (breaking the binding) so the user can size the panel.
    // A fresh open (new instance) restores the default.
    property real panelW: Math.max(300, Math.min((root.width || 700) - 120, 440))
    property real panelH: Math.max(260, Math.min((root.height || 700) - 140, 420))

    // Folder-internal drag-reorder state. Positions are indexes into
    // folder.appIndices, not entries indexes.
    property int draggedFolderAppPos: -1
    property int reorderTargetFolderAppPos: -1

    // Suppresses per-delegate shift Behaviors during the model-reorder snap
    // on release; same trick as Dock and the main launcher grid.
    property bool suppressAnim: false

    function toggleAppSelection(originalIndex) {
        const arr = selectedAppIndices.slice();
        const pos = arr.indexOf(originalIndex);
        if (pos >= 0) arr.splice(pos, 1);
        else arr.push(originalIndex);
        selectedAppIndices = arr;
        if (arr.length === 0) selectionModeActive = false;
    }

    function deleteSelectedApps() {
        for (let i = 0; i < selectedAppIndices.length; i++)
            CustomApps.removeAppFromFolder(root.folder.id, selectedAppIndices[i]);
        selectedAppIndices = [];
        selectionModeActive = false;
    }

    function exitSelectionMode() {
        selectedAppIndices = [];
        selectionModeActive = false;
    }

    // Exposed to LauncherKeys for stack-style Escape dismissal: closing the
    // per-item menu must take priority over closing the folder itself.
    readonly property bool itemMenuVisible: folderItemMenu.visible
    function closeItemMenu() { folderItemMenu.hide() }

    // Reset the folder-scoped search when the panel retargets to another folder
    // (the Loader keeps this instance alive across folder switches).
    onFolderChanged: if (folderSearchField) folderSearchField.text = ""

    // Clears suppressAnim one tick after a drop. Owned by root (not the grid
    // delegate) so it survives the delegate being destroyed when a drop moves
    // or removes the dragged app — a delegate-scoped Qt.callLater would throw
    // "root is not defined" once its context is torn down.
    Timer {
        id: snapResetTimer
        interval: 0
        repeat: false
        onTriggered: root.suppressAnim = false
    }

    // Non-modal: no input-blocking scrim. The grid behind stays interactive
    // (click another folder to open it, drag apps between folders / out to the
    // root). The panel floats with a shadow and is draggable by its header.

    StyledRectangularShadow {
        target: folderPanel
    }

    Rectangle {
        id: folderPanel
        // Centered by default; the header drag-handle overrides x/y, breaking
        // these bindings, so the panel stays where the user drops it.
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        width: root.panelW
        height: root.panelH
        color: Appearance.m3colors.m3surfaceContainer
        radius: Appearance.rounding.large
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        MouseArea {
            anchors.fill: parent
            // Catch clicks on the panel body so they don't fall through to the
            // grid behind. Right-click surfaces the launcher's add-to-folder
            // menu at the cursor (mapped into root's space).
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    const p = mapToItem(root, mouse.x, mouse.y)
                    root.emptyAreaRightClicked(p.x, p.y)
                }
                mouse.accepted = true
            }
        }

        // Accepts app drags over the panel. For an in-panel (folder) drag it
        // sets overPanel so the eject-to-root drop is suppressed; for a drag
        // coming from the root grid it advertises this folder as the drop
        // target (hoverOpenFolderId) so the root tile's release adds it here.
        DropArea {
            anchors.fill: parent
            enabled: root.draggedFolderAppPos >= 0
                || (root.launcher?.draggedEntryIndex ?? -1) >= 0
            onEntered: (drag) => {
                root.overPanel = true
                if (root.launcher && root.draggedFolderAppPos < 0)
                    root.launcher.hoverOpenFolderId = root.folder?.id ?? ""
                drag.accept(Qt.MoveAction)
            }
            onExited: {
                root.overPanel = false
                if (root.launcher) root.launcher.hoverOpenFolderId = ""
            }
        }

        // Header strip is a drag handle that repositions the whole panel
        // (clamped to the launcher bounds). Declared below the ColumnLayout in
        // stacking, so the header buttons / search field still get their input.
        MouseArea {
            id: panelDragHandle
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 64
            cursorShape: Qt.SizeAllCursor
            drag.target: folderPanel
            drag.axis: Drag.XAndYAxis
            drag.threshold: 4
            drag.minimumX: 0
            drag.maximumX: Math.max(0, root.width - folderPanel.width)
            drag.minimumY: 0
            drag.maximumY: Math.max(0, root.height - folderPanel.height)
        }

        transform: Scale {
            id: openScale
            origin.x: folderPanel.width / 2
            origin.y: folderPanel.height / 2
            xScale: 0.92
            yScale: 0.92
        }
        opacity: 0

        NumberAnimation on opacity {
            from: 0; to: 1
            duration: 160
            easing.type: Easing.OutCubic
            running: true
        }
        NumberAnimation {
            target: openScale; property: "xScale"
            from: 0.92; to: 1
            duration: 200
            easing.type: Easing.OutBack; easing.overshoot: 0.8
            running: true
        }
        NumberAnimation {
            target: openScale; property: "yScale"
            from: 0.92; to: 1
            duration: 200
            easing.type: Easing.OutBack; easing.overshoot: 0.8
            running: true
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 40
                    implicitHeight: 40
                    radius: width * 0.28
                    color: (root.folder?.color ?? "").length > 0
                        ? Qt.alpha(root.folder.color, 0.5)
                        : Appearance.m3colors.m3primaryContainer

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "folder_open"
                        iconSize: 22
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: -1

                    StyledText {
                        Layout.fillWidth: true
                        text: root.folder?.name ?? ""
                        color: Appearance.colors.colOnLayer1
                        font {
                            family: Appearance.font.family.title
                            pixelSize: Appearance.font.pixelSize.larger
                            variableAxes: Appearance.font.variableAxes.title
                        }
                        elide: Text.ElideRight
                    }

                    StyledText {
                        text: root.selectionModeActive
                            ? (root.selectedAppIndices.length > 0
                                ? Translation.tr("%1 selected · Esc to cancel").arg(root.selectedAppIndices.length)
                                : Translation.tr("Tap to select · Esc to cancel"))
                            : (folderAppsGrid.count === 0
                                ? Translation.tr("Empty")
                                : folderAppsGrid.count === 1
                                    ? Translation.tr("1 app")
                                    : Translation.tr("%1 apps").arg(folderAppsGrid.count))
                        color: root.selectionModeActive ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    visible: !root.selectionModeActive
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 36
                    implicitHeight: 36
                    onClicked: {
                        LauncherState.binarySelectorTargetFolderId = root.folder?.id ?? ""
                        LauncherState.binarySelectorOpen = true
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "add"
                        iconSize: 20
                    }

                    VimiumTarget {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: -5
                        anchors.topMargin: -5
                        registry: root.registry
                        participates: !root.selectionModeActive
                        onActivated: {
                            LauncherState.binarySelectorTargetFolderId = root.folder?.id ?? ""
                            LauncherState.binarySelectorOpen = true
                        }
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.selectionModeActive
                    enabled: root.selectedAppIndices.length > 0
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 36
                    implicitHeight: 36
                    onClicked: root.deleteSelectedApps()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "delete_sweep"
                        iconSize: 20
                    }

                    VimiumTarget {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: -5
                        anchors.topMargin: -5
                        registry: root.registry
                        participates: root.selectionModeActive && root.selectedAppIndices.length > 0
                        onActivated: root.deleteSelectedApps()
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 36
                    implicitHeight: 36
                    onClicked: root.closed()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 20
                    }

                    VimiumTarget {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: -5
                        anchors.topMargin: -5
                        registry: root.registry
                        onActivated: root.closed()
                    }
                }
            }

            // Folder-scoped search (#4). Filters this folder's apps only;
            // the launcher's global search is untouched. Wrapped in a plain Item
            // (not a Layout) with a fixed height so the field's internal
            // fillHeight doesn't turn this row into an expanding item that
            // competes with the grid for vertical space.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                visible: folderAppsGrid.count > 0 || root.searchText.length > 0

                ToolbarTextField {
                    id: folderSearchField
                    anchors.fill: parent
                    colBackground: Appearance.m3colors.m3surfaceContainerHigh
                    placeholderText: Translation.tr("Search in folder")
                    onTextChanged: root.searchText = text
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Escape) {
                            if (text.length > 0) text = ""
                            else root.closed()
                            event.accepted = true
                        }
                    }
                }
            }

            GridView {
                id: folderAppsGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                readonly property int columns: Math.max(1, Math.floor(width / (root.iconSize + 40)))
                cellWidth: width / columns
                cellHeight: root.iconSize + 50
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: StyledScrollBar {}

                model: {
                    const _e = CustomApps.entries
                    const _f = CustomApps.folders
                    if (!root.folder) return []
                    const all = CustomApps.appsInFolder(root.folder.id)
                    const q = root.searchText.trim().toLowerCase()
                    if (q.length === 0) return all
                    return all.filter(a => (a.name || "").toLowerCase().includes(q)
                        || (a.path || "").toLowerCase().includes(q))
                }

                move: Transition {
                    NumberAnimation {
                        properties: "x,y"
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }
                moveDisplaced: Transition {
                    NumberAnimation {
                        properties: "x,y"
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }

                delegate: Item {
                    id: folderAppDelegate
                    required property var modelData
                    required property int index
                    width: folderAppsGrid.cellWidth
                    height: folderAppsGrid.cellHeight

                    readonly property bool isSelected: root.selectedAppIndices.indexOf(folderAppDelegate.modelData._originalIndex) >= 0
                    readonly property bool appRunning: {
                        const _w = HyprlandData.windowList   // subscribe for reactivity
                        return !!folderAppDelegate.modelData?.path
                            && CustomApps.isPathRunning(folderAppDelegate.modelData.path)
                    }

                    // Live reorder shift: tiles between the dragged source
                    // and the current drop target slide one cell toward the
                    // source so the layout reflows in real time.
                    readonly property int _shiftedIndex: {
                        const dragIdx = root.draggedFolderAppPos
                        const dropIdx = root.reorderTargetFolderAppPos
                        if (dragIdx < 0 || dropIdx < 0 || dragIdx === dropIdx) return folderAppDelegate.index
                        if (folderAppDelegate.index === dragIdx) return folderAppDelegate.index
                        if (dragIdx < dropIdx && folderAppDelegate.index > dragIdx && folderAppDelegate.index <= dropIdx)
                            return folderAppDelegate.index - 1
                        if (dragIdx > dropIdx && folderAppDelegate.index >= dropIdx && folderAppDelegate.index < dragIdx)
                            return folderAppDelegate.index + 1
                        return folderAppDelegate.index
                    }
                    readonly property real _shiftDx: {
                        const cols = folderAppsGrid.columns
                        return ((_shiftedIndex % cols) - (folderAppDelegate.index % cols)) * folderAppsGrid.cellWidth
                    }
                    readonly property real _shiftDy: {
                        const cols = folderAppsGrid.columns
                        return (Math.floor(_shiftedIndex / cols) - Math.floor(folderAppDelegate.index / cols)) * folderAppsGrid.cellHeight
                    }

                    Timer {
                        id: folderLongPressTimer
                        interval: 500
                        repeat: false
                        onTriggered: {
                            root.selectionModeActive = true;
                            root.toggleAppSelection(folderAppDelegate.modelData._originalIndex);
                            folderAppArea.longPressActivated = true;
                        }
                    }

                    // Visuals (and the MouseArea that drags them) live inside this
                    // wrapper so the live-shift Translate moves the visual but
                    // NOT the DropArea declared as a sibling below. With the
                    // DropArea inside the translated subtree, hovering a target
                    // tile would shift it left, slide its DropArea out from
                    // under the cursor, fire onExited, revert the shift, and
                    // oscillate every frame.
                    Item {
                        id: visualWrapper
                        anchors.fill: parent

                        transform: Translate {
                            x: folderAppDelegate._shiftDx
                            y: folderAppDelegate._shiftDy
                            Behavior on x {
                                enabled: !root.suppressAnim
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            Behavior on y {
                                enabled: !root.suppressAnim
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }

                        VimiumTarget {
                            x: 4
                            y: 4
                            registry: root.registry
                            onActivated: {
                                if (root.selectionModeActive) {
                                    root.toggleAppSelection(folderAppDelegate.modelData._originalIndex)
                                    return
                                }
                                CustomApps.activate(folderAppDelegate.modelData)
                                LauncherState.appLauncherOpen = false
                                root.closed()
                            }
                        }

                    Rectangle {
                        id: folderAppTile
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: Appearance.rounding.normal
                        color: folderAppArea.pressed
                            ? Appearance.colors.colLayer2Active
                            : folderAppArea.containsMouse
                                ? Appearance.colors.colLayer2Hover
                                : "transparent"

                        Drag.active: folderAppArea.drag.active && !root.selectionModeActive
                        Drag.source: folderAppArea
                        Drag.hotSpot.x: width / 2
                        Drag.hotSpot.y: height / 2
                        Drag.supportedActions: Qt.MoveAction

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        states: State {
                            name: "dragging"
                            when: folderAppTile.Drag.active
                            PropertyChanges {
                                target: folderAppTile
                                anchors.fill: undefined
                                anchors.margins: 0
                                opacity: 0.88
                                scale: 1.04
                                z: 50
                            }
                            ParentChange {
                                // Float over the whole launcher (panel + grid),
                                // not just the panel, so the tile can be dropped
                                // on another folder or out to the root grid.
                                target: folderAppTile
                                parent: root.innerLayer ? root.innerLayer : folderPanel
                            }
                        }

                        Behavior on scale {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            visible: folderAppDelegate.isSelected
                            color: Appearance.colors.colPrimary
                            opacity: 0.15
                            z: 1
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            visible: folderAppDelegate.isSelected
                            color: "transparent"
                            border.width: 2
                            border.color: Appearance.colors.colPrimary
                            z: 2
                        }

                        Rectangle {
                            visible: folderAppDelegate.isSelected
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.topMargin: 4
                            anchors.rightMargin: 4
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
                            anchors.fill: parent
                            radius: parent.radius
                            visible: root.reorderTargetFolderAppPos === folderAppDelegate.index
                                && root.draggedFolderAppPos !== folderAppDelegate.index
                            color: Appearance.colors.colPrimaryContainer
                            opacity: 0.35

                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }

                        Rectangle {
                            visible: folderAppDelegate.appRunning && !folderAppDelegate.isSelected
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottomMargin: 3
                            implicitWidth: 6
                            implicitHeight: 6
                            radius: height / 2
                            color: Appearance.colors.colPrimary
                            z: 3
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            Image {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: root.iconSize
                                Layout.preferredHeight: root.iconSize
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                source: {
                                    const icon = folderAppDelegate.modelData.icon || ""
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
                                text: folderAppDelegate.modelData.name
                            }
                        }
                    }

                    MouseArea {
                        id: folderAppArea
                        property bool longPressActivated: false
                        // True once an actual drag gesture began, so a plain
                        // click never triggers move/reorder/eject on release.
                        property bool didDrag: false
                        anchors.fill: parent
                        anchors.margins: 4
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        // Reorder/drag disabled while searching: the filtered
                        // model's indices don't map to folder.appIndices.
                        drag.target: (root.selectionModeActive || root.searchText.length > 0)
                            ? null : folderAppTile
                        drag.threshold: 8
                        preventStealing: true

                        onPressed: (mouse) => {
                            if (mouse.button === Qt.LeftButton) {
                                longPressActivated = false;
                                didDrag = false;
                                root.draggedFolderAppPos = folderAppDelegate.index;
                                // Feed the launcher's drag state so the grid's
                                // folder/eject drop targets react to this drag.
                                if (root.launcher)
                                    root.launcher.draggedEntryIndex = folderAppDelegate.modelData._originalIndex;
                                if (!root.selectionModeActive)
                                    folderLongPressTimer.start();
                            }
                        }
                        onPositionChanged: {
                            if (drag.active) {
                                didDrag = true;
                                if (folderLongPressTimer.running)
                                    folderLongPressTimer.stop();
                            }
                        }
                        onReleased: {
                            folderLongPressTimer.stop();
                            const launcher = root.launcher;
                            const reorderTarget = root.reorderTargetFolderAppPos;
                            const fromPos = folderAppDelegate.index;
                            const idx = folderAppDelegate.modelData._originalIndex;
                            const inSelection = root.selectionModeActive;
                            // Snapshot drop state before reset.
                            const hoverFolder = launcher?.hoverFolderId ?? "";
                            const wasOverPanel = root.overPanel;
                            // Dropped over the grid but not on a folder and not
                            // an in-panel reorder → eject to the root grid.
                            const eject = !wasOverPanel && hoverFolder.length === 0 && reorderTarget < 0;
                            root.suppressAnim = true;
                            root.draggedFolderAppPos = -1;
                            root.reorderTargetFolderAppPos = -1;
                            root.overPanel = false;
                            if (launcher) {
                                launcher.draggedEntryIndex = -1;
                                launcher.hoverFolderId = "";
                            }
                            // Only act on an actual drag — a plain click (left to
                            // launch, right for the menu) must never move/eject.
                            if (didDrag && !inSelection && root.folder) {
                                // Precedence: drop on another folder > in-panel
                                // reorder > eject to the root grid.
                                if (hoverFolder.length > 0 && hoverFolder !== root.folder.id) {
                                    CustomApps.addAppToFolder(hoverFolder, idx);
                                } else if (reorderTarget >= 0 && reorderTarget !== fromPos) {
                                    CustomApps.moveAppInFolder(root.folder.id, fromPos, reorderTarget);
                                } else if (eject) {
                                    CustomApps.removeAppFromFolder(root.folder.id, idx);
                                }
                            }
                            didDrag = false;
                            snapResetTimer.restart();
                        }
                        onCanceled: {
                            folderLongPressTimer.stop();
                            root.suppressAnim = true;
                            root.draggedFolderAppPos = -1;
                            root.reorderTargetFolderAppPos = -1;
                            root.overPanel = false;
                            if (root.launcher) {
                                root.launcher.draggedEntryIndex = -1;
                                root.launcher.hoverFolderId = "";
                            }
                            snapResetTimer.restart();
                        }

                        onClicked: (mouse) => {
                            if (longPressActivated) {
                                longPressActivated = false;
                                return;
                            }
                            if (mouse.button === Qt.RightButton) {
                                const pos = folderAppArea.mapToItem(folderPanel, mouse.x, mouse.y)
                                folderItemMenu.targetAppIndex = folderAppDelegate.modelData._originalIndex
                                folderItemMenu.targetAppName = folderAppDelegate.modelData.name
                                folderItemMenu.openAt(pos.x, pos.y)
                                return;
                            }
                            if (root.selectionModeActive) {
                                root.toggleAppSelection(folderAppDelegate.modelData._originalIndex);
                                return;
                            }
                            if (folderAppTile.Drag.active) return;
                            CustomApps.activate(folderAppDelegate.modelData)
                            LauncherState.appLauncherOpen = false
                            root.closed()
                        }
                    }
                    } // visualWrapper

                    DropArea {
                        id: folderReorderDropArea
                        anchors.fill: parent
                        anchors.margins: 4
                        // Active only for in-panel reorder drags. For a drag
                        // coming from the root grid these tiles must stay
                        // transparent so the event reaches the panel-wide drop
                        // zone underneath — otherwise a full folder (tiles cover
                        // every pixel) can't accept a new app.
                        enabled: !folderAppTile.Drag.active && root.draggedFolderAppPos >= 0
                        onEntered: (drag) => {
                            if (root.draggedFolderAppPos < 0) return
                            if (root.draggedFolderAppPos === folderAppDelegate.index) return
                            root.reorderTargetFolderAppPos = folderAppDelegate.index
                            drag.accept(Qt.MoveAction)
                        }
                        onExited: {
                            if (root.reorderTargetFolderAppPos === folderAppDelegate.index) {
                                root.reorderTargetFolderAppPos = -1
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                Layout.bottomMargin: 12
                visible: folderAppsGrid.count === 0
                spacing: 4

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.searchText.length > 0 ? "search_off" : "drag_pan"
                    iconSize: 36
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.searchText.length > 0
                        ? Translation.tr("No matches in this folder")
                        : Translation.tr("Drag apps here to add them")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }

        // Bottom-right corner resize grip: drag to size the panel (the pointer
        // position in root space becomes the panel's new bottom-right corner).
        MouseArea {
            id: resizeGrip
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 22
            height: 22
            z: 30
            cursorShape: Qt.SizeFDiagCursor
            onPositionChanged: (m) => {
                if (!pressed) return
                const p = mapToItem(root, m.x, m.y)
                root.panelW = Math.max(300, Math.min(p.x - folderPanel.x, root.width - folderPanel.x - 8))
                root.panelH = Math.max(260, Math.min(p.y - folderPanel.y, root.height - folderPanel.y - 8))
            }

            MaterialSymbol {
                anchors.centerIn: parent
                rotation: 90
                text: "open_in_full"
                iconSize: 13
                color: Appearance.colors.colSubtext
                opacity: 0.6
            }
        }

        MouseArea {
            anchors.fill: parent
            z: 8
            visible: folderItemMenu.visible
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: event => {
                const inMenu = (event.x >= folderItemMenu.x && event.x <= folderItemMenu.x + folderItemMenu.width
                    && event.y >= folderItemMenu.y && event.y <= folderItemMenu.y + folderItemMenu.height)
                const subAbsX = folderItemMenu.x + folderItemSubmenu.x
                const subAbsY = folderItemMenu.y + folderItemSubmenu.y
                const inSub = folderItemSubmenu.visible
                    && event.x >= subAbsX && event.x <= subAbsX + folderItemSubmenu.width
                    && event.y >= subAbsY && event.y <= subAbsY + folderItemSubmenu.height
                if (!inMenu && !inSub) {
                    folderItemMenu.hide()
                    event.accepted = true
                } else {
                    event.accepted = false
                }
            }
        }

        Rectangle {
            id: folderItemMenu
            z: 9
            visible: false
            implicitWidth: 200
            implicitHeight: folderItemMenuColumn.implicitHeight + 12
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            property int targetAppIndex: -1
            property string targetAppName: ""
            // Same sticky-open trick as AppContextMenu: a click-opened submenu
            // must not be auto-dismissed by the hover-out timer.
            property bool _submenuStickyOpen: false

            readonly property string currentGpu: {
                const e = CustomApps.entries[targetAppIndex]
                return e?.gpu ?? ""
            }

            function openAt(cx, cy) {
                const maxX = folderPanel.width - folderItemMenu.width - 4
                const maxY = folderPanel.height - folderItemMenu.height - 4
                folderItemMenu.x = Math.max(4, Math.min(cx - folderItemMenu.width / 2, maxX))
                folderItemMenu.y = Math.max(4, Math.min(cy, maxY))
                folderItemMenu.visible = true
            }

            function hide() {
                folderItemOpenSubmenuTimer.stop()
                folderItemCloseSubmenuTimer.stop()
                folderItemSubmenu.visible = false
                folderItemMenu._submenuStickyOpen = false
                folderItemMenu.visible = false
            }

            function _toggleSubmenu() {
                folderItemOpenSubmenuTimer.stop()
                folderItemCloseSubmenuTimer.stop()
                folderItemSubmenu.visible = !folderItemSubmenu.visible
                folderItemMenu._submenuStickyOpen = folderItemSubmenu.visible
            }

            function _launchWithGpu(gpu) {
                const idx = folderItemMenu.targetAppIndex
                if (idx < 0) return
                CustomApps.setEntryGpu(idx, gpu)
                folderItemMenu.hide()
                CustomApps.launch(CustomApps.entries[idx])
                LauncherState.appLauncherOpen = false
                root.closed()
            }

            function _setDefaultGpu(gpu) {
                const idx = folderItemMenu.targetAppIndex
                if (idx < 0) return
                CustomApps.setEntryGpu(idx, gpu)
                folderItemMenu.hide()
            }

            Timer {
                id: folderItemOpenSubmenuTimer
                interval: 100
                repeat: false
                onTriggered: folderItemSubmenu.visible = true
            }

            Timer {
                id: folderItemCloseSubmenuTimer
                interval: 200
                repeat: false
                onTriggered: folderItemSubmenu.visible = false
            }

            StyledRectangularShadow {
                target: folderItemMenu
                visible: folderItemMenu.visible
            }

            ColumnLayout {
                id: folderItemMenuColumn
                anchors.fill: parent
                anchors.margins: 6
                spacing: 0

                MenuButton {
                    Layout.fillWidth: true
                    symbolName: "drive_file_rename_outline"
                    buttonText: Translation.tr("Rename")
                    onClicked: {
                        const idx = folderItemMenu.targetAppIndex
                        const name = folderItemMenu.targetAppName
                        folderItemMenu.hide()
                        root.renameAppRequested(idx, name)
                    }
                }

                MenuButton {
                    Layout.fillWidth: true
                    symbolName: "playlist_remove"
                    buttonText: Translation.tr("Remove from folder")
                    onClicked: {
                        const idx = folderItemMenu.targetAppIndex
                        folderItemMenu.hide()
                        CustomApps.removeAppFromFolder(root.folder.id, idx)
                    }
                }

                MenuButton {
                    id: folderItemMoreButton
                    Layout.fillWidth: true
                    // Always available now: the submenu holds "Move to…" (and
                    // GPU options on hybrid systems).
                    visible: true
                    symbolName: "chevron_right"
                    buttonText: Translation.tr("More")
                    onClicked: folderItemMenu._toggleSubmenu()

                    HoverHandler {
                        id: folderItemMoreHover
                        onHoveredChanged: {
                            if (folderItemMoreHover.hovered) {
                                folderItemCloseSubmenuTimer.stop()
                                if (!folderItemSubmenu.visible) folderItemOpenSubmenuTimer.start()
                            } else {
                                folderItemOpenSubmenuTimer.stop()
                                if (!folderItemSubmenuHover.hovered && !folderItemMenu._submenuStickyOpen)
                                    folderItemCloseSubmenuTimer.start()
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: folderItemSubmenu
                z: 11
                visible: false

                width: 200
                height: folderItemSubmenuColumn.implicitHeight + 12

                // Default: right of main menu, aligned to moreButton.
                // Flip horizontally if it would overflow folderPanel; clamp vertically.
                x: {
                    const defaultX = folderItemMenu.width - 2
                    const absoluteRight = folderItemMenu.x + defaultX + folderItemSubmenu.width
                    const panelWidth = folderPanel.width
                    if (absoluteRight > panelWidth - 8) {
                        return -folderItemSubmenu.width + 2
                    }
                    return defaultX
                }

                y: {
                    // folderItemMoreButton.y is in folderItemMenuColumn's
                    // space; submenu.y is in folderItemMenu's. Add the
                    // column's top margin so the submenu lines up with the
                    // anchor row instead of sitting above it.
                    const desired = folderItemMoreButton.y + folderItemMenuColumn.anchors.margins
                    const maxY = folderPanel.height - folderItemMenu.y - folderItemSubmenu.height - 8
                    return Math.max(0, Math.min(desired, maxY))
                }

                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.normal
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                StyledRectangularShadow {
                    target: folderItemSubmenu
                    visible: folderItemSubmenu.visible
                }

                HoverHandler {
                    id: folderItemSubmenuHover
                    onHoveredChanged: {
                        if (folderItemSubmenuHover.hovered) {
                            folderItemCloseSubmenuTimer.stop()
                        } else if (!folderItemMoreHover.hovered && !folderItemMenu._submenuStickyOpen) {
                            folderItemCloseSubmenuTimer.start()
                        }
                    }
                }

                ColumnLayout {
                    id: folderItemSubmenuColumn
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 0

                    // Move the app to another folder (non-drag fallback for #3).
                    Repeater {
                        model: CustomApps.folders
                        delegate: MenuButton {
                            required property var modelData
                            Layout.fillWidth: true
                            visible: modelData.id !== (root.folder?.id ?? "")
                            symbolName: "drive_file_move"
                            buttonText: Translation.tr("Move to %1").arg(modelData.name || "")
                            onClicked: {
                                const idx = folderItemMenu.targetAppIndex
                                folderItemMenu.hide()
                                CustomApps.addAppToFolder(modelData.id, idx)
                            }
                        }
                    }

                    MenuButton {
                        Layout.fillWidth: true
                        visible: folderItemMenu.currentGpu !== "dGPU"
                        symbolName: "developer_board"
                        buttonText: Translation.tr("Launch with dGPU")
                        onClicked: folderItemMenu._launchWithGpu("dGPU")
                    }

                    MenuButton {
                        Layout.fillWidth: true
                        visible: folderItemMenu.currentGpu === "dGPU"
                        symbolName: "memory"
                        buttonText: Translation.tr("Launch with iGPU")
                        onClicked: folderItemMenu._launchWithGpu("iGPU")
                    }

                    MenuButton {
                        Layout.fillWidth: true
                        visible: folderItemMenu.currentGpu !== "dGPU"
                        symbolName: "bookmark_add"
                        buttonText: Translation.tr("Set default to dGPU")
                        onClicked: folderItemMenu._setDefaultGpu("dGPU")
                    }

                    MenuButton {
                        Layout.fillWidth: true
                        visible: folderItemMenu.currentGpu === "dGPU"
                        symbolName: "bookmark_add"
                        buttonText: Translation.tr("Set default to iGPU")
                        onClicked: folderItemMenu._setDefaultGpu("iGPU")
                    }
                }
            }
        }
    }
}
