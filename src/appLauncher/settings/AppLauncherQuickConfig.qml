import qs
import "../../state"
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import ".."
import "../vimium"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ContentPage {
    id: page
    readonly property int index: 0
    property bool register: false
    forceWidth: true
    interactive: false

    property var registry: null

    ContentSection {
        icon: "straighten"
        title: Translation.tr("Appearance")
        Layout.fillWidth: true

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            Rectangle {
                id: sizePreview
                readonly property int previewSize: Persistent.states.appLauncher?.iconSize ?? 64
                implicitWidth: 112
                implicitHeight: 112
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                border.width: 1
                border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.9)

                Rectangle {
                    id: previewSquircle
                    anchors.centerIn: parent
                    width: sizePreview.previewSize
                    height: sizePreview.previewSize
                    radius: width * 0.28
                    color: Appearance.m3colors.m3surfaceContainerHigh

                    Behavior on width {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on height {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "apps"
                        iconSize: Math.round(previewSquircle.width * 0.5)
                        color: Appearance.colors.colPrimary
                    }
                }

                Rectangle {
                    anchors {
                        right: parent.right
                        bottom: parent.bottom
                        margins: 6
                    }
                    implicitWidth: sizeLabel.implicitWidth + 12
                    implicitHeight: sizeLabel.implicitHeight + 4
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimary

                    StyledText {
                        id: sizeLabel
                        anchors.centerIn: parent
                        text: sizePreview.previewSize + "px"
                        color: Appearance.colors.colOnPrimary
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                ConfigSlider {
                    Layout.fillWidth: true
                    text: Translation.tr("Icon size")
                    buttonIcon: "photo_size_select_large"
                    from: 32
                    to: 96
                    value: Persistent.states.appLauncher?.iconSize ?? 64
                    onValueChanged: {
                        if (!Persistent.states.appLauncher) return
                        const rounded = Math.round(value)
                        if (Persistent.states.appLauncher.iconSize !== rounded) {
                            Persistent.states.appLauncher.iconSize = rounded
                        }
                    }
                }

                StyledText {
                    Layout.leftMargin: 36
                    Layout.topMargin: 2
                    text: Translation.tr("Affects tiles in the launcher grid")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: "open_in_full"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                ConfigSelectionArray {
                    Layout.fillWidth: true
                    options: [
                        { displayName: Translation.tr("Fullscreen"), icon: "fullscreen", value: "current" },
                        { displayName: Translation.tr("Windowed"), icon: "aspect_ratio", value: "settings" }
                    ]
                    currentValue: Persistent.states.appLauncher?.windowSize ?? "settings"
                    onSelected: (value) => {
                        if (Persistent.states.appLauncher)
                            Persistent.states.appLauncher.windowSize = value
                    }
                    registry: page.registry
                }

                StyledText {
                    Layout.leftMargin: 36
                    Layout.topMargin: 2
                    text: (Persistent.states.appLauncher?.windowSize ?? "settings") === "current"
                    ? Translation.tr("Fullscreen uses the entire screen")
                    : Translation.tr("Windowed: 900×750")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }
    }

    ContentSection {
        icon: "folder"
        title: Translation.tr("Folders")
        Layout.fillWidth: true

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: CustomApps.folders

                delegate: Rectangle {
                    id: folderRow
                    required property int index
                    required property var modelData
                    readonly property int appCount: (modelData.appIndices || []).length
                    readonly property var previewIcons: CustomApps.folderPreviewIcons(modelData, 4)

                    Layout.fillWidth: true
                    implicitHeight: 64
                    radius: Appearance.rounding.normal
                    color: rowHover.containsMouse
                        ? Appearance.colors.colLayer1Hover
                        : Appearance.colors.colLayer1

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    MouseArea {
                        id: rowHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        propagateComposedEvents: true
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 12

                        Rectangle {
                            id: folderTile
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 44
                            implicitHeight: 44
                            radius: width * 0.28
                            color: Appearance.m3colors.m3surfaceContainerHigh

                            FolderPreviewGrid {
                                anchors.centerIn: parent
                                width: parent.width * 0.72
                                height: parent.height * 0.72
                                visible: folderRow.appCount > 0
                                icons: folderRow.previewIcons
                            }

                            MaterialSymbol {
                                visible: folderRow.appCount === 0
                                anchors.centerIn: parent
                                text: "folder"
                                iconSize: 22
                                color: Appearance.colors.colOnLayer1
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: folderRow.modelData.name || ""
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: folderRow.appCount === 0
                                    ? Translation.tr("Empty")
                                    : folderRow.appCount === 1
                                        ? Translation.tr("1 app")
                                        : Translation.tr("%1 apps").arg(folderRow.appCount)
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                elide: Text.ElideRight
                            }
                        }

                        RippleButton {
                            Layout.alignment: Qt.AlignVCenter
                            buttonRadius: Appearance.rounding.full
                            implicitWidth: 36
                            implicitHeight: 36
                            opacity: rowHover.containsMouse ? 1 : 0.55
                            colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colError, 0.85)
                            colRipple: ColorUtils.transparentize(Appearance.colors.colError, 0.7)
                            onClicked: CustomApps.removeFolderAt(folderRow.index)
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: "delete"
                                iconSize: 20
                                color: Appearance.colors.colOnLayer1
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
                                onActivated: CustomApps.removeFolderAt(folderRow.index)
                            }
                        }
                    }
                }
            }

            Item {
                visible: CustomApps.folders.length === 0
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                implicitHeight: emptyColumn.implicitHeight + 28

                ColumnLayout {
                    id: emptyColumn
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "create_new_folder"
                        iconSize: 32
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("No folders yet")
                        color: Appearance.colors.colOnLayer1
                        font.weight: Font.Medium
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Right-click in the launcher to add one")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }

        }
    }
}
