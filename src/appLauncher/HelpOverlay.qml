import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    anchors.fill: parent

    signal closed()

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    component KeyChip: Rectangle {
        id: keyChip
        property string label: ""
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2
        implicitWidth: chipText.implicitWidth + 16
        implicitHeight: chipText.implicitHeight + 8

        StyledText {
            id: chipText
            anchors.centerIn: parent
            text: keyChip.label
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer1
        }
    }

    component HelpRow: RowLayout {
        id: helpRow
        property string keyLabel: ""
        property string descText: ""
        Layout.fillWidth: true
        spacing: 12

        KeyChip {
            label: helpRow.keyLabel
        }

        StyledText {
            Layout.fillWidth: true
            text: helpRow.descText
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.normal
            wrapMode: Text.Wrap
        }
    }

    component SubHeading: ColumnLayout {
        id: subHeading
        property string label: ""
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 6

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Appearance.colors.colLayer2
            opacity: 0.5
        }

        StyledText {
            text: subHeading.label
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Bold
            opacity: 0.8
        }
    }

    component HelpNote: StyledText {
        Layout.fillWidth: true
        Layout.topMargin: 2
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
        opacity: 0.7
        wrapMode: Text.Wrap
    }

    component HelpSection: ColumnLayout {
        id: helpSection
        property string title: ""
        default property alias rows: rowContainer.data
        Layout.fillWidth: true
        spacing: 8

        StyledText {
            text: helpSection.title
            color: Appearance.colors.colOnLayer1
            font {
                family: Appearance.font.family.title
                pixelSize: Appearance.font.pixelSize.large
                variableAxes: Appearance.font.variableAxes.title
            }
        }

        Rectangle {
            Layout.fillWidth: true
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal
            implicitHeight: rowContainer.implicitHeight + 24

            ColumnLayout {
                id: rowContainer
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 12
                }
                spacing: 8
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.m3colors.m3surfaceContainerLow
        radius: Appearance.rounding.normal

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                spacing: 8

                RippleButton {
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 36
                    implicitHeight: 36
                    onClicked: root.closed()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "arrow_back"
                        iconSize: 20
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    text: Translation.tr("Help")
                    color: Appearance.colors.colOnLayer0
                    font {
                        family: Appearance.font.family.title
                        pixelSize: Appearance.font.pixelSize.large
                        variableAxes: Appearance.font.variableAxes.title
                    }
                }
            }

            ScrollView {
                id: scroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                ColumnLayout {
                    width: scroll.availableWidth
                    spacing: 16

                    HelpSection {
                        title: Translation.tr("Keyboard")

                        HelpRow {
                            keyLabel: "Esc"
                            descText: Translation.tr("Close / cancel current mode")
                        }
                        HelpRow {
                            keyLabel: "Ctrl + D"
                            descText: Translation.tr("Detach window")
                        }
                        HelpRow {
                            keyLabel: "Ctrl + /"
                            descText: Translation.tr("Show this help")
                        }
                    }

                    HelpSection {
                        title: Translation.tr("Search")

                        HelpRow {
                            keyLabel: "/"
                            descText: Translation.tr("Focus the search field")
                        }
                        HelpRow {
                            keyLabel: Translation.tr("Type")
                            descText: Translation.tr("Filter apps by name or path (matches inside folders too)")
                        }
                        HelpRow {
                            keyLabel: "Enter"
                            descText: Translation.tr("Launch the first matching app")
                        }
                        HelpRow {
                            keyLabel: "Tab"
                            descText: Translation.tr("Activate vimium hints over the filtered results")
                        }
                        HelpRow {
                            keyLabel: "Esc"
                            descText: Translation.tr("Clear the search; press again to close the launcher")
                        }
                    }

                    HelpSection {
                        title: Translation.tr("Mouse & Drag")

                        HelpRow {
                            keyLabel: Translation.tr("Click")
                            descText: Translation.tr("Launch app")
                        }
                        HelpRow {
                            keyLabel: Translation.tr("Right-click")
                            descText: Translation.tr("Context menu / add app")
                        }
                        HelpRow {
                            keyLabel: Translation.tr("Long-press")
                            descText: Translation.tr("Enter selection mode")
                        }
                        HelpRow {
                            keyLabel: Translation.tr("Drag app onto folder")
                            descText: Translation.tr("Group apps")
                        }
                        HelpRow {
                            keyLabel: Translation.tr("Drop file from file manager")
                            descText: Translation.tr("Add to launcher")
                        }
                    }

                    HelpSection {
                        title: Translation.tr("Context menu — App")

                        HelpRow {
                            keyLabel: Translation.tr("Rename")
                            descText: Translation.tr("Rename this application")
                        }
                        HelpRow {
                            keyLabel: Translation.tr("Remove from launcher")
                            descText: Translation.tr("Remove this app from the launcher")
                        }

                        SubHeading {
                            label: Translation.tr("More submenu")
                        }

                        HelpRow {
                            keyLabel: Translation.tr("Launch with dGPU / iGPU")
                            descText: Translation.tr("Launch this app once using the chosen GPU")
                        }
                        HelpRow {
                            keyLabel: Translation.tr("Set default to dGPU / iGPU")
                            descText: Translation.tr("Change the default GPU for this app (no launch)")
                        }

                        HelpNote {
                            text: Translation.tr("Available only on hybrid-GPU systems")
                        }
                    }

                    HelpSection {
                        title: Translation.tr("Context menu — Folder")

                        HelpRow {
                            keyLabel: Translation.tr("Open folder")
                            descText: Translation.tr("Open the folder view")
                        }
                        HelpRow {
                            keyLabel: Translation.tr("Rename")
                            descText: Translation.tr("Rename this folder")
                        }
                        HelpRow {
                            keyLabel: Translation.tr("Delete folder")
                            descText: Translation.tr("Delete the folder; apps stay in the launcher")
                        }

                        SubHeading {
                            label: Translation.tr("More submenu")
                        }

                        HelpRow {
                            keyLabel: Translation.tr("Set default to dGPU / iGPU")
                            descText: Translation.tr("Change the default GPU for the folder (no launch)")
                        }

                        HelpNote {
                            text: Translation.tr("Available only on hybrid-GPU systems")
                        }
                    }

                    HelpSection {
                        title: Translation.tr("Context menu — Empty area")

                        HelpRow {
                            keyLabel: Translation.tr("Add application")
                            descText: Translation.tr("Pick a binary to add as a launcher item")
                        }
                        HelpRow {
                            keyLabel: Translation.tr("Add folder")
                            descText: Translation.tr("Create a new empty folder")
                        }
                    }

                    HelpSection {
                        title: Translation.tr("Folder view")

                        HelpRow {
                            keyLabel: Translation.tr("Drag app into folder")
                            descText: Translation.tr("Add app to this folder")
                        }
                        HelpRow {
                            keyLabel: Translation.tr("Drag app out of folder")
                            descText: Translation.tr("Remove app from this folder")
                        }
                        HelpRow {
                            keyLabel: Translation.tr("Right-click on app")
                            descText: Translation.tr("App context menu (Rename / Remove from folder / More)")
                        }
                    }

                    HelpSection {
                        title: Translation.tr("Selection mode")

                        HelpRow {
                            keyLabel: Translation.tr("Long-press")
                            descText: Translation.tr("Enter selection mode")
                        }
                        HelpRow {
                            keyLabel: Translation.tr("Tap")
                            descText: Translation.tr("Toggle app selection")
                        }
                        HelpRow {
                            keyLabel: "Esc"
                            descText: Translation.tr("Exit selection mode")
                        }
                    }

                    HelpSection {
                        title: Translation.tr("Vimium hints")

                        HelpRow {
                            keyLabel: "F"
                            descText: Translation.tr("Activate hints in current view")
                        }
                        HelpRow {
                            keyLabel: "Tab"
                            descText: Translation.tr("Activate hints from the search field (filter stays applied)")
                        }
                        HelpRow {
                            keyLabel: Translation.tr("Type letters")
                            descText: Translation.tr("Trigger highlighted action")
                        }
                        HelpRow {
                            keyLabel: Translation.tr("Backspace")
                            descText: Translation.tr("Erase one character")
                        }
                        HelpRow {
                            keyLabel: "Esc"
                            descText: Translation.tr("Cancel")
                        }
                    }
                }
            }
        }
    }
}
