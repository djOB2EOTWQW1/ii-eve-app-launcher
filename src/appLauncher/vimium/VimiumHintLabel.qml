import QtQuick
import qs.modules.common

Rectangle {
    id: root
    property string hintText: ""
    property string typedText: ""
    property bool vimiumActive: false

    visible: vimiumActive && hintText.length > 0 && hintText.startsWith(typedText)

    width: label.implicitWidth + 10
    height: label.implicitHeight + 6
    color: "#f5e100"
    border.color: "#a89800"
    border.width: 1
    radius: 3
    z: 300

    Text {
        id: label
        anchors.centerIn: parent
        text: root.hintText
        font.pixelSize: 11
        font.bold: true
        font.family: "monospace"
        color: "#1a1200"
    }
}
