import qs
import "../state"
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "settings"
import "vimium"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

// Main launcher surface: header bar, app/folder grid, settings overlay,
// folder viewer, context menu, rename dialog, external-drop receiver.
// Instantiated both inside the attached PanelWindow and the detached
// FloatingWindow so the behaviour is identical in either mode.
MouseArea {
    id: root

    anchors.fill: parent
    acceptedButtons: Qt.RightButton
    // Right-click on the empty grid area must reach this MouseArea even
    // when an inner element (GridView, Rectangle) sits between us and the
    // cursor; without this Qt may swallow the press silently.
    propagateComposedEvents: true

    readonly property int iconSize: LauncherPersist?.iconSize ?? 64

    // Tracks which folder tile the current drag is hovering over.
    // Cleared on drop/release. Uses folder id to survive model updates.
    property string hoverFolderId: ""
    property int draggedEntryIndex: -1
    // Active folder-drag id; "" when no folder is being dragged.
    property string draggedFolderId: ""
    // Reorder target — entryIndex of the app tile being hovered, or -1.
    property int reorderTargetEntryIndex: -1
    // Reorder target — folderId of the folder tile being hovered, or "".
    property string reorderTargetFolderId: ""
    // True while an external file-manager drag (source === null) hovers over the launcher.
    property bool externalDragHover: false

    // Suppresses the per-delegate shift Behaviors during the brief window
    // around model reorders so nothing animates between snapping the drag
    // state to idle and the model rebuild settling.
    property bool suppressAnim: false

    property string searchText: ""
    function clearSearch() {
        if (searchField.text.length > 0) searchField.text = ""
        if (root.searchText.length > 0) root.searchText = ""
    }
    function focusSearch() {
        searchField.forceActiveFocus()
    }
    readonly property bool searchActive: searchText.length > 0
    readonly property bool recentsStripVisible: !root.searchActive
        && !root.selectionModeActive
        && appGrid.count > 0
        && CustomApps.recentApps.length > 0

    function launchFirstMatch() {
        const gm = root.gridModel
        if (!gm || gm.length === 0) return
        const first = gm[0]
        if (!first) return
        if (first.appIndices) {
            folderViewer.open(first)
            return
        }
        if (root.selectionModeActive) return
        CustomApps.activate(first)
        LauncherState.appLauncherOpen = false
    }

    function activateVimiumFromSearch() {
        const gm = root.gridModel
        if (!gm || gm.length === 0) return
        if (root.parent) root.parent.forceActiveFocus()
        root.vimiumActive = true
        root.vimiumTyped = ""
    }

    // Wrapper cache keyed by entry index. Lets _resolveKey return the same JS
    // object across rebuilds so the delegate's `modelData` reference is stable.
    property var _entryWrapperCache: ({})
    function _entryWrapper(i) {
        const e = CustomApps.entries[i]
        if (!e) return null
        let w = _entryWrapperCache[i]
        if (!w || w.name !== e.name || w.path !== e.path || w.icon !== e.icon || w.gpu !== e.gpu) {
            w = { name: e.name, path: e.path, icon: e.icon, gpu: e.gpu, _originalIndex: i }
            _entryWrapperCache[i] = w
        }
        return w
    }

    function _itemKey(it) {
        if (!it) return ""
        if (it.appIndices) return "f:" + (it.id || "")
        return "a:" + (it._originalIndex ?? -1)
    }
    function _resolveKey(key) {
        if (!key) return null
        if (key.charAt(0) === "f") {
            const id = key.substring(2)
            const folders = CustomApps.folders || []
            for (let i = 0; i < folders.length; i++) {
                if (folders[i].id === id) return folders[i]
            }
            return null
        }
        if (key.charAt(0) === "a") {
            const idx = parseInt(key.substring(2))
            return root._entryWrapper(idx)
        }
        return null
    }

    function _syncVisibleModel() {
        const want = root.gridModel
        const wantKeys = []
        for (let i = 0; i < want.length; i++) wantKeys.push(root._itemKey(want[i]))
        const wantSet = {}
        for (let i = 0; i < wantKeys.length; i++) wantSet[wantKeys[i]] = true

        // Remove items no longer in the desired set (back-to-front to keep indices valid).
        for (let i = visibleModel.count - 1; i >= 0; i--) {
            if (!wantSet[visibleModel.get(i).key]) visibleModel.remove(i, 1)
        }
        // Walk the desired list, moving or inserting to match its order.
        for (let i = 0; i < wantKeys.length; i++) {
            const wantKey = wantKeys[i]
            if (i >= visibleModel.count) {
                visibleModel.append({ key: wantKey })
                continue
            }
            if (visibleModel.get(i).key === wantKey) continue
            let foundAt = -1
            for (let j = i + 1; j < visibleModel.count; j++) {
                if (visibleModel.get(j).key === wantKey) { foundAt = j; break }
            }
            if (foundAt >= 0) visibleModel.move(foundAt, i, 1)
            else visibleModel.insert(i, { key: wantKey })
        }
    }

    onGridModelChanged: Qt.callLater(_syncVisibleModel)
    Component.onCompleted: _syncVisibleModel()

    ListModel { id: visibleModel }

    // Folder objects pass through unwrapped — the delegate identifies them by
    // the presence of `appIndices` (folders have it, root entries don't).
    readonly property var gridModel: {
        const q = (root.searchText || "").trim().toLowerCase()
        if (q === "") {
            return (CustomApps.folders || []).concat(CustomApps.rootEntries || [])
        }
        // While searching, flatten the namespace: every matching app shows up
        // regardless of its folder. Folders themselves are intentionally not
        // included — the user is looking for apps.
        const out = []
        const entries = CustomApps.entries || []
        for (let i = 0; i < entries.length; i++) {
            const e = entries[i]
            if (!e) continue
            const name = (e.name || "").toLowerCase()
            const path = (e.path || "").toLowerCase()
            if (name.includes(q) || path.includes(q)) {
                const w = root._entryWrapper(i)
                if (w) out.push(w)
            }
        }
        return out
    }

    readonly property int gridColumns: appGrid.columns
    readonly property real gridCellWidth: appGrid.cellWidth
    readonly property real gridCellHeight: appGrid.cellHeight

    // Position in gridModel of the currently dragged tile (app or folder), or -1.
    readonly property int draggedGridIndex: {
        const arr = root.gridModel
        if (root.draggedEntryIndex >= 0) {
            for (let i = 0; i < arr.length; i++) {
                const it = arr[i]
                if (it && !it.appIndices && it._originalIndex === root.draggedEntryIndex) return i
            }
            return -1
        }
        if (root.draggedFolderId.length > 0) {
            for (let i = 0; i < arr.length; i++) {
                const it = arr[i]
                if (it && it.appIndices && it.id === root.draggedFolderId) return i
            }
        }
        return -1
    }

    // Position in gridModel of the current reorder target, or -1. Folder
    // add-targets (hoverFolderId without reorderTarget*) intentionally don't
    // count — they don't reorder the grid.
    readonly property int dropGridIndex: {
        const arr = root.gridModel
        if (root.reorderTargetEntryIndex >= 0) {
            for (let i = 0; i < arr.length; i++) {
                const it = arr[i]
                if (it && !it.appIndices && it._originalIndex === root.reorderTargetEntryIndex) return i
            }
            return -1
        }
        if (root.reorderTargetFolderId.length > 0) {
            for (let i = 0; i < arr.length; i++) {
                const it = arr[i]
                if (it && it.appIndices && it.id === root.reorderTargetFolderId) return i
            }
        }
        return -1
    }

    VimiumRegistry { id: mainReg; referenceItem: innerLayerRect }
    VimiumRegistry { id: settingsReg; referenceItem: settingsOverlay.item }
    VimiumRegistry { id: folderReg; referenceItem: folderViewer.item }

    readonly property alias mainRegistry: mainReg
    readonly property alias settingsRegistry: settingsReg
    readonly property alias folderRegistry: folderReg

    property alias vimiumActive: mainReg.active
    property alias vimiumTyped: mainReg.typed
    property alias settingsVimiumActive: settingsReg.active
    property alias settingsVimiumTyped: settingsReg.typed
    property alias folderVimiumActive: folderReg.active
    property alias folderVimiumTyped: folderReg.typed

    property bool selectionModeActive: false
    property var selectedAppIndices: []

    readonly property bool inSettings: settingsOverlay.shown
    readonly property bool isFolderOpen: folderViewer.active
    readonly property bool isFolderSelectionModeActive: folderViewer.item?.selectionModeActive ?? false
    readonly property bool helpOverlayShown: helpOverlay.shown
    readonly property bool canActivateVimium: !contextMenu.visible && !renameDialog.visible && !helpOverlay.shown

    // Surface popup-menu visibility for LauncherKeys so Escape can dismiss the
    // menu first instead of cascading straight into closeFolder/launcher hide.
    readonly property bool contextMenuVisible: contextMenu.visible
    readonly property bool folderItemMenuVisible: folderViewer.item?.itemMenuVisible ?? false
    readonly property bool renameDialogVisible: renameDialog.visible
    function closeContextMenu() { contextMenu.hide() }
    function closeFolderItemMenu() { folderViewer.item?.closeItemMenu() }
    function cancelRenameDialog() { renameDialog.cancel() }
    function closeSettings() {
        settingsOverlay.shown = false
        settingsReg.active = false
        settingsReg.typed = ""
    }

    function toggleHelp() {
        const opening = !helpOverlay.shown
        if (opening) {
            vimiumActive = false; vimiumTyped = ""
            folderVimiumActive = false; folderVimiumTyped = ""
            settingsVimiumActive = false; settingsVimiumTyped = ""
        }
        helpOverlay.shown = opening
    }

    function toggleAppSelection(entryIndex) {
        const arr = selectedAppIndices.slice()
        const pos = arr.indexOf(entryIndex)
        if (pos >= 0) arr.splice(pos, 1)
        else arr.push(entryIndex)
        selectedAppIndices = arr
        if (arr.length === 0) selectionModeActive = false
    }

    function deleteSelectedApps() {
        const sorted = selectedAppIndices.slice().sort((a, b) => b - a)
        for (let i = 0; i < sorted.length; i++) CustomApps.removeAppAt(sorted[i])
        selectedAppIndices = []
        selectionModeActive = false
    }

    function exitSelectionMode() {
        selectedAppIndices = []
        selectionModeActive = false
    }

    function exitFolderSelectionMode() {
        folderViewer.item?.exitSelectionMode()
    }

    function closeFolder() {
        folderViewer.close()
    }

    onInSettingsChanged: if (inSettings) exitSelectionMode()

    Connections {
        target: GlobalStates
        function onAppLauncherOpenChanged() {
            if (LauncherState.appLauncherOpen) return
            // Hard-reset every transient mode when the launcher is dismissed
            // so the next open starts clean — otherwise vimium hints, partial
            // typed prefixes and an open rename dialog all bleed across
            // sessions when closed via global shortcut / dismiss-on-blur.
            root.exitSelectionMode()
            root.vimiumActive = false; root.vimiumTyped = ""
            root.folderVimiumActive = false; root.folderVimiumTyped = ""
            root.settingsVimiumActive = false; root.settingsVimiumTyped = ""
            root.clearSearch()
            renameDialog.cancel()
        }
    }

    onPressed: event => {
        if (settingsOverlay.shown) {
            event.accepted = false
            return
        }
        // acceptedButtons restricts us to RightButton, so this is unconditional.
        contextMenu.selectedAppIndex = -1
        contextMenu.selectedFolderId = ""
        contextMenu.openFolderId = folderViewer.active ? (folderViewer.folder?.id ?? "") : ""
        contextMenu.x = event.x - contextMenu.width / 2
        contextMenu.y = event.y
        contextMenu.openAt()
        event.accepted = true
    }

    Rectangle {
        id: innerLayerRect
        anchors.fill: parent
        anchors.margins: 10
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1

        Item {
            id: headerBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            implicitHeight: 58

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: headerRightButtons.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: 20
                anchors.topMargin: 10
                anchors.bottomMargin: 6
                spacing: 0

                StyledText {
                    text: Translation.tr("Apps")
                    color: Appearance.colors.colOnLayer1
                    font {
                        family: Appearance.font.family.title
                        pixelSize: Appearance.font.pixelSize.larger
                        variableAxes: Appearance.font.variableAxes.title
                    }
                }

                StyledText {
                    topPadding: -1
                    text: root.selectionModeActive
                        ? (root.selectedAppIndices.length > 0
                            ? Translation.tr("%1 selected · Esc to cancel").arg(root.selectedAppIndices.length)
                            : Translation.tr("Tap to select · Esc to cancel"))
                        : (appGrid.count === 0
                            ? Translation.tr("Right-click to add an application")
                            : Translation.tr("%1 items · drag onto a folder to group").arg(appGrid.count))
                    color: root.selectionModeActive
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }

            Row {
                id: headerRightButtons
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 12
                anchors.topMargin: 10
                spacing: 4

                RippleButton {
                    id: deleteSelectionButton
                    visible: root.selectionModeActive
                    enabled: root.selectedAppIndices.length > 0
                    focusPolicy: Qt.NoFocus
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
                        registry: root.mainRegistry
                        participates: root.selectionModeActive && root.selectedAppIndices.length > 0
                        onActivated: root.deleteSelectedApps()
                    }
                }

                RippleButton {
                    id: addAppButton
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 36
                    implicitHeight: 36
                    visible: !settingsOverlay.shown && !root.selectionModeActive
                    onClicked: {
                        LauncherState.binarySelectorTargetFolderId = ""
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
                        registry: root.mainRegistry
                        participates: !settingsOverlay.shown && !root.selectionModeActive
                        onActivated: {
                            LauncherState.binarySelectorTargetFolderId = ""
                            LauncherState.binarySelectorOpen = true
                        }
                    }
                }

                RippleButton {
                    id: settingsButton
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 36
                    implicitHeight: 36
                    visible: !settingsOverlay.shown && !root.selectionModeActive
                    onClicked: settingsOverlay.shown = true
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "settings"
                        iconSize: 20
                    }

                    VimiumTarget {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: -5
                        anchors.topMargin: -5
                        registry: root.mainRegistry
                        participates: !settingsOverlay.shown && !root.selectionModeActive
                        onActivated: settingsOverlay.shown = true
                    }
                }
            }
        }

        Loader {
            id: recentsStripLoader
            anchors.top: headerBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            active: root.recentsStripVisible
            visible: active
            sourceComponent: LauncherRecentsStrip {
                launcher: root
            }
        }

        Item {
            anchors.fill: parent
            visible: appGrid.count === 0 && !root.externalDragHover

            PagePlaceholder {
                icon: root.searchActive ? "search_off" : "apps"
                title: root.searchActive
                    ? Translation.tr("No matches")
                    : Translation.tr("No applications yet")
                description: root.searchActive
                    ? Translation.tr("Try a different query")
                    : Translation.tr("Right-click anywhere to add one")
                descriptionHorizontalAlignment: Text.AlignHCenter
            }

            StyledText {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: searchToolbar.visible ? searchToolbar.height + 28 : 24
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !root.searchActive
                text: Translation.tr("Show help: Ctrl + /")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                opacity: 0.7
            }
        }

        GridView {
            id: appGrid
            anchors.fill: parent
            anchors.margins: 14
            anchors.topMargin: headerBar.height + 4
                + (root.recentsStripVisible ? recentsStripLoader.implicitHeight + 6 : 0)
            anchors.bottomMargin: searchToolbar.visible ? searchToolbar.height + 28 : 14
            visible: count > 0
            readonly property int columns: Math.max(1, Math.floor(width / (root.iconSize + 76)))
            cellWidth: width / columns
            cellHeight: root.iconSize + 76
            clip: true
            interactive: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: StyledScrollBar {}

            model: visibleModel

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
            displaced: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: 220
                    easing.type: Easing.OutCubic
                }
            }

            delegate: AppGridDelegate {
                id: gridDelegateInstance
                required property string key
                width: appGrid.cellWidth
                height: appGrid.cellHeight
                launcher: root
                innerLayer: innerLayerRect
                modelData: root._resolveKey(key)
                // Behavior-based fade-in: bindings (unlike transitions) don't
                // get broken by interrupted animations, so the delegate always
                // settles to fully opaque/full-scale.
                property bool _appeared: false
                opacity: gridDelegateInstance._appeared ? 1 : 0
                scale: gridDelegateInstance._appeared ? 1 : 0.85
                Behavior on opacity {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
                Component.onCompleted: gridDelegateInstance._appeared = true
                onOpenFolderRequested: (folder) => folderViewer.open(folder)
                onContextMenuForAppRequested: (entryIndex, launcherX, launcherY) => {
                    contextMenu.selectedAppIndex = entryIndex
                    contextMenu.selectedFolderId = ""
                    contextMenu.x = launcherX - contextMenu.width / 2
                    contextMenu.y = launcherY
                    contextMenu.openAt()
                }
                onContextMenuForFolderRequested: (folderId, launcherX, launcherY) => {
                    contextMenu.selectedFolderId = folderId
                    contextMenu.selectedAppIndex = -1
                    contextMenu.x = launcherX - contextMenu.width / 2
                    contextMenu.y = launcherY
                    contextMenu.openAt()
                }
            }
        }

        Toolbar {
            id: searchToolbar
            z: 14
            colBackground: Appearance.colors.colSecondaryContainer
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            visible: !settingsOverlay.shown
                && !folderViewer.active
                && !helpOverlay.shown
                && !root.externalDragHover

            ToolbarTextField {
                id: searchField
                placeholderText: focus
                    ? Translation.tr("Search · Enter to launch · Tab for hints")
                    : Translation.tr("Hit \"/\" to search")
                clip: true
                font.pixelSize: Appearance.font.pixelSize.small
                colBackground: Qt.alpha(Appearance.colors.colOnSecondaryContainer, 0.05)
                color: Appearance.colors.colOnSecondaryContainer
                placeholderTextColor: Qt.alpha(Appearance.colors.colOnSecondaryContainer, 0.6)
                // Keep Tab/Backtab from being eaten by Qt's focus traversal so
                // our Keys handler can intercept Tab to activate vimium.
                activeFocusOnTab: false
                onTextChanged: root.searchText = text
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        if (text.length > 0) text = ""
                        else if (root.parent) root.parent.forceActiveFocus()
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.launchFirstMatch()
                        event.accepted = true
                        return
                    }
                    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                        root.activateVimiumFromSearch()
                        event.accepted = true
                        return
                    }
                }
            }

            IconToolbarButton {
                implicitWidth: height
                onClicked: root.clearSearch()
                text: "close"
                colText: Appearance.colors.colOnSecondaryContainer
                StyledToolTip {
                    text: Translation.tr("Clear search")
                }
            }
        }

        FadeLoader {
            id: settingsOverlay
            anchors.fill: parent
            z: 15
            shown: false
            sourceComponent: Rectangle {
                id: settingsRect
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.normal

                property var settingsRef: null

                Component.onCompleted: settingsRect.settingsRef = launcherSettings

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                AppLauncherSettings {
                    id: launcherSettings
                    anchors.fill: parent
                    registry: root.settingsRegistry
                    onClosed: settingsOverlay.shown = false
                }
            }
        }

        // Overlay shown while an external binary is dragged over the launcher (detach mode).
        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: parent.radius
            visible: root.externalDragHover
            z: 25
            color: "transparent"
            border.width: 2
            border.color: Appearance.colors.colPrimary

            Behavior on border.color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Appearance.colors.colPrimaryContainer
                opacity: 0.12
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 10

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "add_circle"
                    iconSize: 48
                    color: Appearance.colors.colPrimary
                    opacity: 0.9
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Drop to add application")
                    color: Appearance.colors.colPrimary
                    font.pixelSize: Appearance.font.pixelSize.normal
                }
            }
        }

        // Android 16 style expanded folder: dimmed backdrop + centered panel.
        Loader {
            id: folderViewer
            anchors.fill: parent
            z: 20
            active: false
            // Track folder by id so `folder` re-resolves against the current
            // CustomApps.folders snapshot — the cached object goes stale after
            // rename / reorder when the model rebuilds entries.
            property string folderId: ""
            readonly property var folder: {
                if (!folderId) return null
                const folders = CustomApps.folders || []
                for (let i = 0; i < folders.length; i++) {
                    if (folders[i].id === folderId) return folders[i]
                }
                return null
            }

            function open(f) {
                folderViewer.folderId = f?.id ?? ""
                folderViewer.active = true
            }

            function close() {
                folderViewer.active = false
                folderViewer.folderId = ""
            }

            onActiveChanged: {
                if (!active) {
                    root.folderVimiumActive = false
                    root.folderVimiumTyped = ""
                }
            }

            sourceComponent: AppFolderViewer {
                folder: folderViewer.folder
                iconSize: root.iconSize
                registry: root.folderRegistry
                onClosed: folderViewer.close()
                onRenameAppRequested: (appIndex, currentName) => renameDialog.openForApp(appIndex, currentName)
                // The viewer swallows backdrop / empty-panel right-clicks so they
                // don't trigger a context menu for whichever AppGridDelegate sits
                // behind the scrim. We still want the launcher's empty-context
                // menu (Add application / Add folder, scoped to the open folder)
                // to appear at the click position, so re-open it here from the
                // signaled coordinates.
                onEmptyAreaRightClicked: (x, y) => {
                    const pos = folderViewer.item.mapToItem(root, x, y)
                    contextMenu.selectedAppIndex = -1
                    contextMenu.selectedFolderId = ""
                    contextMenu.openFolderId = folderViewer.folder?.id ?? ""
                    contextMenu.x = pos.x - contextMenu.width / 2
                    contextMenu.y = pos.y
                    contextMenu.openAt()
                }
            }
        }

        FadeLoader {
            id: helpOverlay
            anchors.fill: parent
            z: 21
            shown: false
            sourceComponent: HelpOverlay {
                onClosed: helpOverlay.shown = false
            }
        }
    }

    AppContextMenu {
        id: contextMenu
        onFolderOpenRequested: (folder) => folderViewer.open(folder)
        onRenameAppRequested: (appIndex, currentName) => renameDialog.openForApp(appIndex, currentName)
        onRenameFolderRequested: (folderId, currentName) => renameDialog.openForFolder(folderId, currentName)
    }

    RenameDialog {
        id: renameDialog
        anchors.fill: parent
    }

    // Dismisses the context menu when the user clicks outside its bounds.
    MouseArea {
        anchors.fill: parent
        visible: contextMenu.visible
        z: 9
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: event => {
            const localX = event.x
            const localY = event.y
            if (localX < contextMenu.x || localX > contextMenu.x + contextMenu.width
                || localY < contextMenu.y || localY > contextMenu.y + contextMenu.height) {
                contextMenu.hide()
                event.accepted = true
            } else {
                event.accepted = false
            }
        }
    }

    // Receives file drops from external apps (file managers) in detach mode.
    // Ignores internal QML drags (drag.source !== null) so folder drop targets
    // remain functional.
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]

        // Any modal overlay (settings / help / rename / context menu) hides
        // the launcher's drop affordance — accepting drops while the user
        // can't see the destination would silently shove items into the
        // root grid out from under whatever they were doing.
        readonly property bool _modalOpen: settingsOverlay.shown
            || helpOverlay.shown
            || renameDialog.visible
            || contextMenu.visible

        onEntered: (drag) => {
            if (drag.source !== null) return
            if (_modalOpen) return
            root.externalDragHover = true
            drag.accept(Qt.CopyAction)
        }
        onExited: {
            root.externalDragHover = false
        }
        onDropped: (drop) => {
            root.externalDragHover = false
            if (_modalOpen) return
            const raw = drop.getDataAsString("text/uri-list")
            if (!raw) return
            const urls = raw.split(/\r?\n/).filter(u => u.trim().length > 0)
            const targetFolderId = folderViewer.active ? (folderViewer.folder?.id ?? "") : ""
            for (let i = 0; i < urls.length; i++) {
                const filePath = urls[i].trim()
                // Only auto-place into the open folder when the drop creates a
                // genuinely new entry. Otherwise an external drop would silently
                // move an existing app between folders, which surprises users
                // who expect file drops to behave purely as additions.
                const added = CustomApps.addApp(filePath)
                if (added && targetFolderId.length > 0) {
                    const idx = CustomApps.indexOfPath(filePath)
                    if (idx >= 0) CustomApps.addAppToFolder(targetFolderId, idx)
                }
            }
            drop.accept(Qt.CopyAction)
        }
    }
}
