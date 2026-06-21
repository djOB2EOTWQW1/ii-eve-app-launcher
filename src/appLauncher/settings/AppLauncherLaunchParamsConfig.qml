import qs
import "../../state"
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "../vimium"
import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ContentPage {
    id: page
    forceWidth: true
    interactive: false

    property var registry: null

    readonly property var lp: LauncherPersist?.launchParams ?? null

    // Default Launch Parameters
    ContentSection {
        id: defaultsSection
        icon: "tune"
        title: Translation.tr("Default launch parameters")
        Layout.fillWidth: true

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 8
            rowSpacing: 6

            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "speed"
                text: "mangohud"
                checked: page.lp?.defaultsMangohud ?? false
                onCheckedChanged: {
                    if (page.lp && page.lp.defaultsMangohud !== checked) {
                        page.lp.defaultsMangohud = checked
                    }
                }

                VimiumTarget {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -5
                    anchors.topMargin: -5
                    registry: page.registry
                    onActivated: if (page.lp) page.lp.defaultsMangohud = !page.lp.defaultsMangohud
                }
            }

            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "sports_esports"
                text: "gamemoderun"
                checked: page.lp?.defaultsGamemoderun ?? false
                onCheckedChanged: {
                    if (page.lp && page.lp.defaultsGamemoderun !== checked) {
                        page.lp.defaultsGamemoderun = checked
                    }
                }

                VimiumTarget {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -5
                    anchors.topMargin: -5
                    registry: page.registry
                    onActivated: if (page.lp) page.lp.defaultsGamemoderun = !page.lp.defaultsGamemoderun
                }
            }

            ConfigSwitch {
                Layout.fillWidth: true
                Layout.columnSpan: 2
                buttonIcon: "tune"
                enabled: (page.lp?.defaultsMangohud ?? false)
                opacity: enabled ? 1 : 0.55
                text: Translation.tr("Use mangohud user config")
                checked: page.lp?.defaultsUseMangohudConfig ?? false
                onCheckedChanged: {
                    if (page.lp && page.lp.defaultsUseMangohudConfig !== checked) {
                        page.lp.defaultsUseMangohudConfig = checked
                    }
                }

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                VimiumTarget {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -5
                    anchors.topMargin: -5
                    registry: page.registry
                    onActivated: if (page.lp) page.lp.defaultsUseMangohudConfig = !page.lp.defaultsUseMangohudConfig
                }
            }
        }

        ContentSubsectionLabel {
            Layout.fillWidth: true
            Layout.topMargin: 6
            text: Translation.tr("Extra")
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: extraInput.implicitHeight + 18
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: extraInput.activeFocus ? 2 : 1
            border.color: extraInput.activeFocus
                ? Appearance.colors.colPrimary
                : ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.85)

            Behavior on border.color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            StyledTextInput {
                id: extraInput
                anchors.fill: parent
                anchors.margins: 10
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                text: page.lp?.defaultsExtra ?? ""
                onEditingFinished: {
                    if (page.lp && page.lp.defaultsExtra !== text) {
                        page.lp.defaultsExtra = text
                    }
                }
                Keys.onEscapePressed: {
                    if (page.lp && page.lp.defaultsExtra !== text) {
                        page.lp.defaultsExtra = text
                    }
                    extraInput.focus = false
                }
            }

            StyledText {
                anchors.left: parent.left
                anchors.leftMargin: 10 + (extraInput.padding ?? 0)
                anchors.verticalCenter: parent.verticalCenter
                visible: extraInput.text.length === 0 && !extraInput.activeFocus
                text: "WINEDEBUG=-all RADV_PERFTEST=video_decode"
                color: Appearance.colors.colSubtext
                opacity: 0.7
                font.pixelSize: extraInput.font.pixelSize
            }
        }
    }

    // Per-app Parameters
    ContentSection {
        id: perAppSection
        icon: "terminal"
        title: Translation.tr("Per-app parameters")
        Layout.fillWidth: true

        property string selectedPath: ""

        readonly property var nativeApps: {
            const out = []
            const list = CustomApps.entries || []
            for (let i = 0; i < list.length; i++) {
                const e = list[i]
                if (!e || !e.path) continue
                if (String(e.path).toLowerCase().endsWith('.exe')) continue
                out.push(e)
            }
            return out
        }

        readonly property var selectedEntry: CustomApps.perAppMap[perAppSection.selectedPath] || null

        function _writePerApp(path, params, useDefaults, matchClass) {
            if (!page.lp || !path) return
            const trimmed = String(params || "").trim()
            const cls = String(matchClass || "").trim()
            let next = {}
            try { next = JSON.parse(page.lp.perAppJson || "{}") } catch (e) {}
            // Drop the record only when it carries no meaningful data: empty
            // params, defaults left on, and no class override.
            if (trimmed.length === 0 && useDefaults && cls.length === 0) {
                delete next[path]
            } else {
                const rec = { params: trimmed, useDefaults: !!useDefaults }
                if (cls.length > 0) rec.matchClass = cls
                next[path] = rec
            }
            page.lp.perAppJson = JSON.stringify(next)
        }

        // Inline-expanding picker. Pushing siblings down is intentional: a Popup
        // floating above ConfigSwitch causes visual overlap (#design feedback).
        component BinaryPicker: ColumnLayout {
            id: picker
            Layout.fillWidth: true
            spacing: 6

            property bool expanded: false

            function toggleExpanded() { picker.expanded = !picker.expanded }

            Rectangle {
                id: anchorRow
                Layout.fillWidth: true
                implicitHeight: 56
                radius: Appearance.rounding.normal
                color: anchorMouse.containsMouse
                    ? Appearance.colors.colLayer1Hover
                    : Appearance.colors.colLayer1
                border.width: picker.expanded ? 2 : 1
                border.color: picker.expanded
                    ? Appearance.colors.colPrimary
                    : ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.78)

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                Behavior on border.color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 12

                    MaterialSymbol {
                        text: "apps"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            if (perAppSection.selectedPath.length === 0)
                                return Translation.tr("Select a binary")
                            const list = CustomApps.entries || []
                            for (let i = 0; i < list.length; i++) {
                                if (list[i].path === perAppSection.selectedPath)
                                    return list[i].name || list[i].path
                            }
                            return perAppSection.selectedPath
                        }
                        color: Appearance.colors.colOnLayer1
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }

                    MaterialSymbol {
                        text: picker.expanded ? "expand_less" : "expand_more"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                }

                MouseArea {
                    id: anchorMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: picker.toggleExpanded()
                }

                VimiumTarget {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -5
                    anchors.topMargin: -5
                    registry: page.registry
                    onActivated: binaryPicker.toggleExpanded()
                }
            }

            // Inline list. Layout.preferredHeight collapses to 0 when not expanded.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: picker.expanded
                    ? Math.min(perAppSection.nativeApps.length, 6) * 42 + 8
                    : 0
                visible: Layout.preferredHeight > 0
                clip: true
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.82)

                Behavior on Layout.preferredHeight {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                ListView {
                    id: listView
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    model: perAppSection.nativeApps
                    boundsBehavior: Flickable.StopAtBounds
                    spacing: 2

                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        width: ListView.view.width
                        height: 40
                        radius: Appearance.rounding.small
                        color: rowMouse.containsMouse
                            ? Appearance.colors.colLayer1Hover
                            : (modelData.path === perAppSection.selectedPath
                                ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85)
                                : "transparent")

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            Image {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                source: {
                                    const icon = modelData.icon || ""
                                    if (icon.startsWith("/")) return "file://" + icon
                                    return Quickshell.iconPath(icon || "application-x-executable", "application-x-executable")
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.name || modelData.path
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                perAppSection.selectedPath = modelData.path
                                picker.expanded = false
                            }
                        }
                    }
                }
            }
        }

        BinaryPicker {
            id: binaryPicker
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 6
            implicitHeight: paramsInput.implicitHeight + 18
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            opacity: perAppSection.selectedPath.length > 0 ? 1 : 0.4
            enabled: perAppSection.selectedPath.length > 0
            border.width: paramsInput.activeFocus ? 2 : 1
            border.color: paramsInput.activeFocus
                ? Appearance.colors.colPrimary
                : ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.85)

            Behavior on border.color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            StyledTextInput {
                id: paramsInput
                anchors.fill: parent
                anchors.margins: 10
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                text: perAppSection.selectedEntry?.params ?? ""

                // Debounced auto-save: editingFinished only fires on Enter or
                // graceful focus-loss, so an abrupt unload (launcher close, page
                // switch) would otherwise drop unsaved keystrokes. Skip the
                // write when text matches the stored value, otherwise re-binds
                // from `selectedEntry` would needlessly create entries (and
                // accidentally opt the binary out of defaults via the fallback).
                function _flushSave() {
                    saveDebounce.stop()
                    if (perAppSection.selectedPath.length === 0) return
                    const cur = perAppSection.selectedEntry
                    const curParams = String(cur?.params ?? "").trim()
                    const newParams = String(paramsInput.text || "").trim()
                    if (newParams === curParams) return
                    perAppSection._writePerApp(
                        perAppSection.selectedPath,
                        paramsInput.text,
                        cur?.useDefaults ?? true,
                        cur?.matchClass ?? ""
                    )
                }
                Timer {
                    id: saveDebounce
                    interval: 250
                    repeat: false
                    onTriggered: paramsInput._flushSave()
                }
                onTextChanged: {
                    if (perAppSection.selectedPath.length === 0) return
                    saveDebounce.restart()
                }
                onEditingFinished: paramsInput._flushSave()
                Keys.onEscapePressed: {
                    paramsInput._flushSave()
                    paramsInput.focus = false
                }
                Component.onDestruction: paramsInput._flushSave()
            }

            StyledText {
                anchors.left: parent.left
                anchors.leftMargin: 10 + (paramsInput.padding ?? 0)
                anchors.verticalCenter: parent.verticalCenter
                visible: paramsInput.text.length === 0 && !paramsInput.activeFocus
                text: Translation.tr("Local parameters for this binary")
                color: Appearance.colors.colSubtext
                opacity: 0.7
                font.pixelSize: paramsInput.font.pixelSize
            }
        }

        ConfigSwitch {
            Layout.fillWidth: true
            Layout.topMargin: 4
            enabled: perAppSection.selectedPath.length > 0
            buttonIcon: "auto_fix"
            text: Translation.tr("Apply default parameters")
            checked: (perAppSection.selectedEntry?.useDefaults ?? true) !== false
            onCheckedChanged: {
                if (perAppSection.selectedPath.length === 0) return
                const cur = (perAppSection.selectedEntry?.useDefaults ?? true) !== false
                if (cur === checked) return
                perAppSection._writePerApp(
                    perAppSection.selectedPath,
                    perAppSection.selectedEntry?.params ?? "",
                    checked,
                    perAppSection.selectedEntry?.matchClass ?? ""
                )
            }

            VimiumTarget {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: -5
                anchors.topMargin: -5
                registry: page.registry
                onActivated: {
                    if (!page.lp) return
                    if (perAppSection.selectedPath.length === 0) return
                    const cur = (perAppSection.selectedEntry?.useDefaults ?? true) !== false
                    perAppSection._writePerApp(
                        perAppSection.selectedPath,
                        perAppSection.selectedEntry?.params ?? "",
                        !cur,
                        perAppSection.selectedEntry?.matchClass ?? ""
                    )
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 6
            implicitHeight: classInput.implicitHeight + 18
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            opacity: perAppSection.selectedPath.length > 0 ? 1 : 0.4
            enabled: perAppSection.selectedPath.length > 0
            border.width: classInput.activeFocus ? 2 : 1
            border.color: classInput.activeFocus
                ? Appearance.colors.colPrimary
                : ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.85)

            Behavior on border.color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            StyledTextInput {
                id: classInput
                anchors.fill: parent
                anchors.margins: 10
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                text: perAppSection.selectedEntry?.matchClass ?? ""

                function _flushSave() {
                    classSaveDebounce.stop()
                    if (perAppSection.selectedPath.length === 0) return
                    const cur = perAppSection.selectedEntry
                    const curCls = String(cur?.matchClass ?? "").trim()
                    const newCls = String(classInput.text || "").trim()
                    if (newCls === curCls) return
                    perAppSection._writePerApp(
                        perAppSection.selectedPath,
                        cur?.params ?? "",
                        cur?.useDefaults ?? true,
                        classInput.text
                    )
                }
                Timer {
                    id: classSaveDebounce
                    interval: 250
                    repeat: false
                    onTriggered: classInput._flushSave()
                }
                onTextChanged: {
                    if (perAppSection.selectedPath.length === 0) return
                    classSaveDebounce.restart()
                }
                onEditingFinished: classInput._flushSave()
                Keys.onEscapePressed: {
                    classInput._flushSave()
                    classInput.focus = false
                }
                Component.onDestruction: classInput._flushSave()
            }

            StyledText {
                anchors.left: parent.left
                anchors.leftMargin: 10 + (classInput.padding ?? 0)
                anchors.verticalCenter: parent.verticalCenter
                visible: classInput.text.length === 0 && !classInput.activeFocus
                text: Translation.tr("Window class (match)")
                color: Appearance.colors.colSubtext
                opacity: 0.7
                font.pixelSize: classInput.font.pixelSize
            }
        }
    }

    // MANGOHUD user config — multiline string exported as MANGOHUD_CONFIG
    // when the toggle in the defaults section is on.
    ContentSection {
        icon: "code_blocks"
        title: Translation.tr("mangohud user config")
        Layout.fillWidth: true

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Comma-separated mangohud options. Used only when mangohud and \"Use mangohud user config\" are both on.")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 120
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: mangohudConfigInput.activeFocus ? 2 : 1
            border.color: mangohudConfigInput.activeFocus
                ? Appearance.colors.colPrimary
                : ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.85)

            Behavior on border.color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            ScrollView {
                anchors.fill: parent
                anchors.margins: 10
                clip: true

                TextArea {
                    id: mangohudConfigInput
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    persistentSelection: true
                    color: Appearance.colors.colOnLayer1
                    font.family: Appearance.font.family.monospace || Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.small
                    background: null
                    text: page.lp?.defaultsMangohudConfig ?? ""
                    onEditingFinished: {
                        if (page.lp && page.lp.defaultsMangohudConfig !== text) {
                            page.lp.defaultsMangohudConfig = text
                        }
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            event.accepted = true
                            if (page.lp && page.lp.defaultsMangohudConfig !== text) {
                                page.lp.defaultsMangohudConfig = text
                            }
                            mangohudConfigInput.focus = false
                            return
                        }
                        if (event.key === Qt.Key_Tab) {
                            event.accepted = true
                            mangohudConfigInput.focus = false
                        }
                    }
                }
            }

            StyledText {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: 14
                anchors.topMargin: 12
                visible: mangohudConfigInput.text.length === 0 && !mangohudConfigInput.activeFocus
                text: "arch,cpu_mhz,cpu_temp,engine_version,gamemode,gpu_core_clock,gpu_mem_clock,gpu_name,gpu_temp,ram,resolution,vkbasalt,vram,vulkan_driver,wine,winesync,font_size=22"
                color: Appearance.colors.colSubtext
                opacity: 0.6
                font.family: mangohudConfigInput.font.family
                font.pixelSize: mangohudConfigInput.font.pixelSize
                wrapMode: Text.WrapAnywhere
                width: parent.width - 28
            }
        }
    }
}
