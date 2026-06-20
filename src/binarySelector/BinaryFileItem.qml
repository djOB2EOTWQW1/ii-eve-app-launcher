import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

MouseArea {
    id: root
    required property var fileModelData
    readonly property bool isDirectory: fileModelData.fileIsDir

    signal activated

    property real itemMargins: 8
    property real itemPadding: 6

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onClicked: root.activated()

    Rectangle {
        id: background
        anchors.fill: parent
        anchors.margins: root.itemMargins
        radius: Appearance.rounding.normal
        color: root.containsMouse
            ? Appearance.colors.colPrimary
            : ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.itemPadding
            spacing: 4

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                DirectoryIcon {
                    anchors.fill: parent
                    fileModelData: root.fileModelData
                    sourceSize.width: parent.width
                    sourceSize.height: parent.height
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.containsMouse ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                text: root.fileModelData.fileName

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }
    }
}
