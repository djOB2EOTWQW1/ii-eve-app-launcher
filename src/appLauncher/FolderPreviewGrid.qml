import QtQuick
import QtQuick.Layouts
import Quickshell

// 2×2 grid of mini app icons shown inside a folder tile squircle.
// Set `icons` to a list of icon-name/path strings (up to 4).
Item {
    id: root
    property var icons: []

    GridLayout {
        anchors.fill: parent
        columns: 2
        rowSpacing: Math.max(2, root.width * 0.056)
        columnSpacing: Math.max(2, root.width * 0.056)

        Repeater {
            model: root.icons

            delegate: Item {
                required property string modelData
                Layout.fillWidth: true
                Layout.fillHeight: true

                Image {
                    anchors.fill: parent
                    anchors.margins: 1
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    source: {
                        const icon = modelData || ""
                        if (icon.startsWith("/")) return "file://" + icon
                        return Quickshell.iconPath(icon, "application-x-executable")
                    }
                }
            }
        }
    }
}
