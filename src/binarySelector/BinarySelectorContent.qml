import qs
import "../state"
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

MouseArea {
    id: rootArea
    property int columns: 5
    property real cellAspectRatio: 1.0
    property string filterText: ""
    property var visibleFiles: []

    // "files" = browse the filesystem for binaries; "apps" = pick an installed
    // application from DesktopEntries. The typed filter applies to both.
    property string mode: "files"

    // Installed applications matching the current filter, sorted by name.
    // DesktopEntries.applications is an UntypedObjectModel; its array lives on
    // `.values` (same access the host's AppSearch uses).
    readonly property var visibleApps: {
        const q = rootArea.filterText.trim().toLowerCase()
        const all = DesktopEntries.applications?.values || []
        const out = []
        for (let i = 0; i < all.length; i++) {
            const e = all[i]
            if (!e || e.noDisplay) continue
            const name = String(e.name || "")
            const gen = String(e.genericName || "")
            if (q.length === 0
                || name.toLowerCase().includes(q)
                || gen.toLowerCase().includes(q)
                || String(e.id || "").toLowerCase().includes(q)) {
                out.push(e)
            }
        }
        out.sort((a, b) => String(a.name || "").localeCompare(String(b.name || "")))
        return out
    }

    function selectApp(entry) {
        if (!entry) return
        const targetFolder = LauncherState.binarySelectorTargetFolderId
        if (CustomApps.addDesktopApp(entry.id) && targetFolder.length > 0) {
            const idx = CustomApps.indexOfPath(`desktop://${entry.id}`)
            if (idx >= 0) CustomApps.addAppToFolder(targetFolder, idx)
        }
        rootArea.filterText = "";
        LauncherState.binarySelectorTargetFolderId = ""
        LauncherState.binarySelectorOpen = false;
    }

    function refreshVisibleFiles() {
        const items = [];
        for (let i = 0; i < folderModel.count; i++) {
            const fileIsDir = folderModel.get(i, "fileIsDir");
            const filePath = folderModel.get(i, "filePath");
            if (fileIsDir || CustomApps.isLikelyBinary(filePath)) {
                items.push({
                    fileName: folderModel.get(i, "fileName"),
                    filePath: filePath,
                    fileIsDir: fileIsDir
                });
            }
        }
        rootArea.visibleFiles = items;
    }

    Timer {
        id: refreshFilesTimer
        interval: 30
        repeat: false
        onTriggered: rootArea.refreshVisibleFiles()
    }

    focus: true
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.BackButton | Qt.ForwardButton

    // The Loader recreates this content on every open, so onCompleted fires
    // exactly when the picker opens: grab keyboard focus (the window uses
    // OnDemand focus) and start from a clean filter.
    Component.onCompleted: {
        rootArea.filterText = "";
        rootArea.forceActiveFocus();
    }

    onPressed: event => {
        if (event.button === Qt.BackButton) folderModel.navigateBack();
        else if (event.button === Qt.ForwardButton) folderModel.navigateForward();
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            LauncherState.binarySelectorOpen = false;
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Up) {
            folderModel.navigateUp();
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Left) {
            folderModel.navigateBack();
            event.accepted = true;
        } else if (event.modifiers & Qt.AltModifier && event.key === Qt.Key_Right) {
            folderModel.navigateForward();
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace) {
            if (rootArea.filterText.length > 0) {
                rootArea.filterText = rootArea.filterText.substring(0, rootArea.filterText.length - 1);
            }
            event.accepted = true;
        } else if (event.text.length > 0 && !(event.modifiers & Qt.ControlModifier)) {
            rootArea.filterText += event.text;
            event.accepted = true;
        }
    }

    FolderListModelWithHistory {
        id: folderModel
        folder: Qt.resolvedUrl(Directories.home)
        caseSensitive: false
        nameFilters: rootArea.filterText.length > 0
            ? rootArea.filterText.split(" ").filter(s => s.length > 0).map(s => `*${s}*`)
            : ["*"]
        showDirs: true
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: false
        showOnlyReadable: true
        sortField: FolderListModel.Name
        sortReversed: false

        onCountChanged: refreshFilesTimer.restart()
        onStatusChanged: refreshFilesTimer.restart()
        onFolderChanged: refreshFilesTimer.restart()
    }

    function selectFile(filePath, isDir) {
        if (isDir) {
            folderModel.folder = Qt.resolvedUrl(filePath);
            return;
        }
        const targetFolder = LauncherState.binarySelectorTargetFolderId
        CustomApps.addApp(filePath)
        if (targetFolder.length > 0) {
            const idx = CustomApps.indexOfPath(filePath)
            if (idx >= 0) CustomApps.addAppToFolder(targetFolder, idx)
        }
        rootArea.filterText = "";
        LauncherState.binarySelectorTargetFolderId = ""
        LauncherState.binarySelectorOpen = false;
    }

    StyledRectangularShadow { target: background }

    Rectangle {
        id: background
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

        RowLayout {
            anchors.fill: parent
            spacing: -4

            // Sidebar: quick directories
            Rectangle {
                Layout.fillHeight: true
                Layout.margins: 4
                implicitWidth: sideColumn.implicitWidth
                color: Appearance.colors.colLayer1
                radius: background.radius - Layout.margins

                ColumnLayout {
                    id: sideColumn
                    anchors.fill: parent
                    spacing: 0

                    StyledText {
                        Layout.margins: 12
                        font {
                            pixelSize: Appearance.font.pixelSize.normal
                            weight: Font.Medium
                        }
                        text: rootArea.mode === "apps"
                            ? Translation.tr("Pick an application")
                            : Translation.tr("Pick a binary")
                    }

                    // Files / Apps mode toggle.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        Layout.bottomMargin: 6
                        spacing: 6

                        Repeater {
                            model: [
                                { m: "files", icon: "folder_open", label: Translation.tr("Files") },
                                { m: "apps", icon: "apps", label: Translation.tr("Apps") }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 32
                                radius: Appearance.rounding.full
                                color: rootArea.mode === modelData.m
                                    ? Appearance.colors.colPrimary
                                    : (toggleArea.containsMouse ? Appearance.colors.colLayer2Hover : "transparent")

                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    MaterialSymbol {
                                        text: modelData.icon
                                        iconSize: 16
                                        color: rootArea.mode === modelData.m
                                            ? Appearance.colors.colOnPrimary
                                            : Appearance.colors.colOnLayer1
                                    }
                                    StyledText {
                                        text: modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: rootArea.mode === modelData.m
                                            ? Appearance.colors.colOnPrimary
                                            : Appearance.colors.colOnLayer1
                                    }
                                }

                                MouseArea {
                                    id: toggleArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: rootArea.mode = modelData.m
                                }
                            }
                        }
                    }

                    Item {
                        visible: rootArea.mode === "files"
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        implicitWidth: 170

                        Flickable {
                            id: sideFlick
                            anchors.fill: parent
                            contentHeight: sideRail.implicitHeight
                            clip: true
                            interactive: contentHeight > height
                            ScrollBar.vertical: StyledScrollBar {
                                visible: sideFlick.interactive
                            }

                            NavigationRailTabArray {
                                id: sideRail
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                expanded: true
                                currentIndex: {
                                    const model = sideRepeater.model;
                                    const current = FileUtils.trimFileProtocol(folderModel.folder.toString());
                                    for (let i = 0; i < model.length; i++) {
                                        const item = model[i];
                                        if (!item.path || item.kind === "separator" || item.kind === "add") continue;
                                        const resolved = FileUtils.trimFileProtocol(Qt.resolvedUrl(item.path).toString());
                                        if (resolved === current) return i;
                                    }
                                    return -1;
                                }

                                Repeater {
                                    id: sideRepeater
                                    model: {
                                        const arr = [
                                            { icon: "home", name: Translation.tr("Home"), path: Directories.home, kind: "nav" },
                                            { icon: "download", name: Translation.tr("Downloads"), path: Directories.downloads, kind: "nav" },
                                            { icon: "desktop_windows", name: Translation.tr("Desktop"), path: `${Directories.home}/Desktop`, kind: "nav" },
                                            { icon: "folder", name: "Applications", path: `${Directories.home}/Applications`, kind: "nav" },
                                            { icon: "", name: "---", path: "", kind: "separator" },
                                            { icon: "deployed_code", name: "/usr/bin", path: "file:///usr/bin", kind: "nav" },
                                            { icon: "deployed_code", name: "/usr/local/bin", path: "file:///usr/local/bin", kind: "nav" },
                                            { icon: "deployed_code", name: "/opt", path: "file:///opt", kind: "nav" },
                                        ];
                                        const userDirs = CustomApps.dirs;
                                        for (let i = 0; i < userDirs.length; i++) {
                                            const p = userDirs[i];
                                            const parts = p.split('/').filter(s => s.length > 0);
                                            const label = parts.length > 0 ? parts[parts.length - 1] : p;
                                            arr.push({ icon: "folder_special", name: label, path: p, kind: "custom", dirIndex: i });
                                        }
                                        arr.push({ icon: "", name: "---", path: "", kind: "separator" });
                                        arr.push({ icon: "create_new_folder", name: Translation.tr("Add dir"), path: "", kind: "add" });
                                        return arr;
                                    }
                                    delegate: Item {
                                        id: railEntry
                                        required property var modelData
                                        required property int index

                                        property real baseSize: 40
                                        property real baseHighlightHeight: 32
                                        readonly property real visualWidth: navBtn.visualWidth

                                        Layout.fillWidth: true
                                        implicitHeight: navBtn.implicitHeight

                                        NavigationRailButton {
                                            id: navBtn
                                            anchors.fill: parent
                                            baseSize: 40
                                            baseHighlightHeight: 32
                                            iconSize: 18
                                            buttonIcon: railEntry.modelData.icon
                                            buttonText: railEntry.modelData.name
                                            expanded: true
                                            toggled: sideRail.currentIndex === railEntry.index
                                            showToggledHighlight: false
                                            enabled: railEntry.modelData.kind !== "separator"
                                            onClicked: {
                                                const md = railEntry.modelData;
                                                if (md.kind === "add") {
                                                    const cur = FileUtils.trimFileProtocol(folderModel.folder.toString());
                                                    CustomApps.addDir(cur);
                                                } else if (md.kind === "nav" || md.kind === "custom") {
                                                    folderModel.folder = Qt.resolvedUrl(md.path);
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.RightButton
                                            enabled: railEntry.modelData.kind === "custom"
                                            onClicked: mouse => {
                                                if (mouse.button === Qt.RightButton) {
                                                    CustomApps.removeDirAt(railEntry.modelData.dirIndex);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Main: address bar + grid
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true

                AddressBar {
                    id: addressBar
                    visible: rootArea.mode === "files"
                    Layout.margins: 4
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    directory: FileUtils.trimFileProtocol(folderModel.folder.toString())
                    radius: background.radius - Layout.margins
                    onNavigateToDirectory: path => {
                        folderModel.folder = Qt.resolvedUrl(path.length === 0 ? "/" : path);
                    }
                }

                Item {
                    id: gridRegion
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    StyledText {
                        visible: rootArea.mode === "apps"
                            ? appsGrid.count === 0
                            : grid.count === 0
                        anchors.centerIn: parent
                        text: rootArea.filterText.length > 0
                            ? Translation.tr("No matches for \"%1\"").arg(rootArea.filterText)
                            : (rootArea.mode === "apps"
                                ? Translation.tr("No applications")
                                : Translation.tr("Empty folder"))
                        font.family: Appearance.font.family.reading
                    }

                    GridView {
                        id: grid
                        visible: rootArea.mode === "files"
                        anchors.fill: parent
                        cellWidth: width / rootArea.columns
                        cellHeight: cellWidth / rootArea.cellAspectRatio
                        interactive: true
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        bottomMargin: filterBar.visible ? filterBar.implicitHeight + 16 : 0
                        ScrollBar.vertical: StyledScrollBar {}
                        model: rootArea.visibleFiles

                        delegate: BinaryFileItem {
                            required property var modelData
                            required property int index
                            fileModelData: modelData
                            width: grid.cellWidth
                            height: grid.cellHeight
                            onActivated: rootArea.selectFile(modelData.filePath, modelData.fileIsDir)
                        }

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: gridRegion.width
                                height: gridRegion.height
                                radius: background.radius
                            }
                        }
                    }

                    GridView {
                        id: appsGrid
                        visible: rootArea.mode === "apps"
                        anchors.fill: parent
                        cellWidth: width / rootArea.columns
                        cellHeight: cellWidth / rootArea.cellAspectRatio
                        interactive: true
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        bottomMargin: filterBar.visible ? filterBar.implicitHeight + 16 : 0
                        ScrollBar.vertical: StyledScrollBar {}
                        model: rootArea.visibleApps

                        delegate: MouseArea {
                            id: appItem
                            required property var modelData
                            required property int index
                            width: appsGrid.cellWidth
                            height: appsGrid.cellHeight
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            onClicked: rootArea.selectApp(appItem.modelData)

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 8
                                radius: Appearance.rounding.normal
                                color: appItem.containsMouse
                                    ? Appearance.colors.colPrimary
                                    : ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)

                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 4

                                    Image {
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        source: Quickshell.iconPath(appItem.modelData?.icon || "", "application-x-executable")
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 6
                                        Layout.rightMargin: 6
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        maximumLineCount: 2
                                        wrapMode: Text.Wrap
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: appItem.containsMouse
                                            ? Appearance.colors.colOnPrimary
                                            : Appearance.colors.colOnLayer0
                                        text: appItem.modelData?.name || ""
                                    }
                                }
                            }
                        }

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: gridRegion.width
                                height: gridRegion.height
                                radius: background.radius
                            }
                        }
                    }

                    Rectangle {
                        id: filterBar
                        visible: rootArea.filterText.length > 0
                        anchors {
                            bottom: parent.bottom
                            horizontalCenter: parent.horizontalCenter
                            bottomMargin: 8
                        }
                        implicitWidth: Math.min(parent.width - 40, filterText.implicitWidth + 40)
                        implicitHeight: 36
                        color: Appearance.m3colors.m3surfaceContainerLow
                        radius: Appearance.rounding.full
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 8

                            MaterialSymbol {
                                text: "filter_alt"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                id: filterText
                                text: rootArea.filterText
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }
    }

}
