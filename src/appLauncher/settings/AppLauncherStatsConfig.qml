import qs
import "../../state"
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "../../common"
import ".."
import "../vimium"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

ContentPage {
    id: page
    forceWidth: true
    interactive: false

    property var registry: null

    // Reactive on launchStatsMap + entries via CustomApps.topApps.
    // NB: not named `top` — ContentPage has a FINAL `top` property.
    readonly property var topList: CustomApps.topApps(5)
    readonly property int maxCount: page.topList.length > 0 ? (page.topList[0]._count || 0) : 0

    function _fmtDate(ms) {
        if (!ms || ms <= 0) return "—"
        return new Date(ms).toLocaleDateString(Qt.locale(), Locale.ShortFormat)
    }

    ContentSection {
        icon: "bar_chart"
        title: Translation.tr("Overview")
        Layout.fillWidth: true

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Total launches card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 84
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 0

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: String(CustomApps.totalLaunches)
                        color: Appearance.colors.colPrimary
                        font {
                            family: Appearance.font.family.title
                            pixelSize: Appearance.font.pixelSize.huge
                            variableAxes: Appearance.font.variableAxes.title
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Total launches")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }

            // Tracking-since card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 84
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 0

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: page._fmtDate(CustomApps.firstLaunchTime)
                        color: Appearance.colors.colPrimary
                        font {
                            family: Appearance.font.family.title
                            pixelSize: Appearance.font.pixelSize.larger
                            variableAxes: Appearance.font.variableAxes.title
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Tracking since")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "leaderboard"
        title: Translation.tr("Most launched")
        Layout.fillWidth: true

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: page.topList

                delegate: Rectangle {
                    id: statRow
                    required property int index
                    required property var modelData
                    readonly property int count: modelData._count || 0

                    Layout.fillWidth: true
                    implicitHeight: 52
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 14
                        spacing: 12

                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: String(statRow.index + 1)
                            color: Appearance.colors.colSubtext
                            font {
                                family: Appearance.font.family.title
                                pixelSize: Appearance.font.pixelSize.normal
                            }
                        }

                        Image {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            source: {
                                const icon = statRow.modelData?.icon || ""
                                if (icon.startsWith("/")) return "file://" + icon
                                return Quickshell.iconPath(icon, "application-x-executable")
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: statRow.modelData?.name || ""
                            color: Appearance.colors.colOnLayer1
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        // Mini bar proportional to the top app's count.
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 60
                            implicitHeight: 6
                            radius: 3
                            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)

                            Rectangle {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * (page.maxCount > 0 ? statRow.count / page.maxCount : 0)
                                height: parent.height
                                radius: parent.radius
                                color: Appearance.colors.colPrimary
                            }
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: Translation.tr("%1×").arg(statRow.count)
                            color: Appearance.colors.colPrimary
                            font.weight: Font.Medium
                        }
                    }
                }
            }

            Item {
                visible: page.topList.length === 0
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
                        text: "query_stats"
                        iconSize: 32
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("No launches recorded yet")
                        color: Appearance.colors.colOnLayer1
                        font.weight: Font.Medium
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Launch some apps to see stats here")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }
        }
    }
}
