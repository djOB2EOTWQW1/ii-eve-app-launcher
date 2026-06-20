import qs
import "../state"
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    visible: false
    z: 30

    property string targetType: ""
    property int appIndex: -1
    property string folderId: ""

    function openForApp(index, name) {
        root.targetType = "app";
        root.appIndex = index;
        root.folderId = "";
        nameField.text = name;
        root.visible = true;
        nameField.selectAll();
        nameField.forceActiveFocus();
    }

    function openForFolder(fid, name) {
        root.targetType = "folder";
        root.appIndex = -1;
        root.folderId = fid;
        nameField.text = name;
        root.visible = true;
        nameField.selectAll();
        nameField.forceActiveFocus();
    }

    function confirm() {
        const trimmed = nameField.text.trim();
        if (trimmed.length === 0) return;
        if (root.targetType === "app") {
            CustomApps.renameAppAt(root.appIndex, trimmed);
        } else {
            CustomApps.renameFolder(root.folderId, trimmed);
        }
        root.visible = false;
    }

    function cancel() {
        root.visible = false;
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colScrim
        opacity: 0.35
        radius: Appearance.rounding.normal

        MouseArea {
            anchors.fill: parent
            onClicked: root.cancel()
        }
    }

    Rectangle {
        id: dialogBox
        anchors.centerIn: parent
        width: 320
        implicitHeight: dialogColumn.implicitHeight + 28
        color: Appearance.m3colors.m3surfaceContainer
        radius: Appearance.rounding.normal
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        MouseArea {
            anchors.fill: parent
            onPressed: (mouse) => mouse.accepted = true
        }

        StyledRectangularShadow {
            target: dialogBox
        }

        ColumnLayout {
            id: dialogColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 12

            StyledText {
                Layout.fillWidth: true
                text: root.targetType === "app"
                    ? Translation.tr("Rename application")
                    : Translation.tr("Rename folder")
                color: Appearance.colors.colOnLayer1
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.normal
                    variableAxes: Appearance.font.variableAxes.title
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: nameField.implicitHeight + 14
                color: Appearance.colors.colLayer1
                radius: Appearance.rounding.normal

                TextField {
                    id: nameField
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.topMargin: 7
                    anchors.bottomMargin: 7
                    background: Item {}
                    color: Appearance.colors.colOnLayer1
                    placeholderTextColor: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.normal
                    selectionColor: Appearance.colors.colPrimaryContainer
                    selectedTextColor: Appearance.colors.colOnPrimaryContainer

                    Keys.onReturnPressed: root.confirm()
                    Keys.onEscapePressed: root.cancel()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 0
                spacing: 8

                Item { Layout.fillWidth: true }

                MenuButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: root.cancel()
                }

                MenuButton {
                    buttonText: Translation.tr("Rename")
                    onClicked: root.confirm()
                }
            }
        }
    }
}
