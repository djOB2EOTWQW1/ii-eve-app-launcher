import qs
import "../state"
import qs.services
import qs.modules.common
import qs.modules.common.widgets
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
    signal closed()
    signal renameAppRequested(int appIndex, string currentName)
    // Right-click on the dimmed backdrop or on empty space inside the folder
    // panel. Coordinates are in `root`'s item space; LauncherContent uses them
    // to position its launcher-wide AppContextMenu (so the user can add apps
    // to the open folder without having to close it first).
    signal emptyAreaRightClicked(real x, real y)

    property bool selectionModeActive: false
    property var selectedAppIndices: []

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

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colScrim
        radius: Appearance.rounding.normal

        MouseArea {
            anchors.fill: parent
            // Swallow RightButton too — otherwise right-clicks on the dimmed
            // backdrop fall through to the AppGridDelegate underneath and
            // open a context menu for whichever app/folder happens to sit
            // behind the scrim. Re-emit as emptyAreaRightClicked so the
            // launcher can still show its "Add to folder" menu here.
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (mouse) => {
                if (mouse.button === Qt.LeftButton) {
                    root.closed()
                } else if (mouse.button === Qt.RightButton) {
                    root.emptyAreaRightClicked(mouse.x, mouse.y)
                }
            }
        }
    }

    Rectangle {
        id: folderPanel
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 560)
        height: Math.min(parent.height - 40, 520)
        color: Appearance.m3colors.m3surfaceContainer
        radius: Appearance.rounding.large
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        MouseArea {
            anchors.fill: parent
            // Left-only on purpose: keeps left-clicks on the panel from
            // closing the folder, while letting right-clicks fall through
            // to the scrim's MouseArea which surfaces the launcher's
            // empty-context menu (Add application / Add folder).
            onPressed: (mouse) => mouse.accepted = true
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
                    color: Appearance.m3colors.m3primaryContainer

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
                    return root.folder ? CustomApps.appsInFolder(root.folder.id) : []
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
                                target: folderAppTile
                                parent: folderPanel
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
                        anchors.fill: parent
                        anchors.margins: 4
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        drag.target: root.selectionModeActive ? null : folderAppTile
                        drag.threshold: 8
                        preventStealing: true

                        onPressed: (mouse) => {
                            if (mouse.button === Qt.LeftButton) {
                                longPressActivated = false;
                                root.draggedFolderAppPos = folderAppDelegate.index;
                                if (!root.selectionModeActive)
                                    folderLongPressTimer.start();
                            }
                        }
                        onPositionChanged: {
                            if (drag.active && folderLongPressTimer.running)
                                folderLongPressTimer.stop();
                        }
                        onReleased: {
                            folderLongPressTimer.stop();
                            const reorderTarget = root.reorderTargetFolderAppPos;
                            const fromPos = folderAppDelegate.index;
                            const inSelection = root.selectionModeActive;
                            root.suppressAnim = true;
                            root.draggedFolderAppPos = -1;
                            root.reorderTargetFolderAppPos = -1;
                            if (!inSelection && reorderTarget >= 0 && reorderTarget !== fromPos && root.folder) {
                                CustomApps.moveAppInFolder(root.folder.id, fromPos, reorderTarget);
                            }
                            Qt.callLater(() => root.suppressAnim = false);
                        }
                        onCanceled: {
                            folderLongPressTimer.stop();
                            root.suppressAnim = true;
                            root.draggedFolderAppPos = -1;
                            root.reorderTargetFolderAppPos = -1;
                            Qt.callLater(() => root.suppressAnim = false);
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
                        enabled: !folderAppTile.Drag.active
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
                    text: "drag_pan"
                    iconSize: 36
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Drag apps here to add them")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
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
                    visible: GpuInfo.hybrid
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
