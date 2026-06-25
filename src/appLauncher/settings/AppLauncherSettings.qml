import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../vimium"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    anchors.fill: parent

    property real contentPadding: 8
    property int currentPage: 0

    property var registry: null

    signal closed()

    function toggleNavExpand() {
        navRail.expanded = !navRail.expanded
    }

    property var pages: [
        {
            name: Translation.tr("Quick"),
            icon: "instant_mix",
            component: "AppLauncherQuickConfig.qml"
        },
        {
            name: Translation.tr("Launch param"),
            icon: "terminal",
            component: "AppLauncherLaunchParamsConfig.qml"
        },
        {
            name: Translation.tr("Stats"),
            icon: "bar_chart",
            component: "AppLauncherStatsConfig.qml"
        }
    ]

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.contentPadding
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 6
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

                VimiumTarget {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -5
                    anchors.topMargin: -5
                    registry: root.registry
                    onActivated: root.closed()
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                text: Translation.tr("App Launcher Settings")
                color: Appearance.colors.colOnLayer0
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.large
                    variableAxes: Appearance.font.variableAxes.title
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.contentPadding

            Item {
                id: navRailWrapper
                Layout.fillHeight: true
                Layout.margins: 5
                implicitWidth: navRail.expanded ? 150 : 64
                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                NavigationRail {
                    id: navRail
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                    }
                    spacing: 10
                    expanded: root.width > 700

                    NavigationRailExpandButton {
                    VimiumTarget {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: -5
                        anchors.topMargin: -5
                        registry: root.registry
                        onActivated: root.toggleNavExpand()
                    }
                }

                    NavigationRailTabArray {
                        currentIndex: root.currentPage
                        expanded: navRail.expanded
                        Repeater {
                            model: root.pages
                            NavigationRailButton {
                                required property var index
                                required property var modelData
                                toggled: root.currentPage === index
                                onPressed: root.currentPage = index
                                expanded: navRail.expanded
                                buttonIcon: modelData.icon
                                buttonText: modelData.name
                                showToggledHighlight: false

                                VimiumTarget {
                                    x: 2
                                    y: 2
                                    registry: root.registry
                                    onActivated: root.currentPage = index
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.normal

                Loader {
                    id: pageLoader
                    anchors.fill: parent
                    opacity: 1.0

                    Component.onCompleted: {
                        source = root.pages[0].component
                    }

                    onLoaded: {
                        if (pageLoader.item) pageLoader.item.registry = root.registry
                    }

                    Connections {
                        target: root
                        function onCurrentPageChanged() {
                            switchAnim.complete()
                            switchAnim.start()
                        }
                    }

                    SequentialAnimation {
                        id: switchAnim

                        NumberAnimation {
                            target: pageLoader
                            properties: "opacity"
                            from: 1
                            to: 0
                            duration: 100
                            easing.type: Appearance.animation.elementMoveExit.type
                            easing.bezierCurve: Appearance.animationCurves.emphasizedFirstHalf
                        }
                        ParallelAnimation {
                            PropertyAction {
                                target: pageLoader
                                property: "source"
                                value: root.pages[root.currentPage].component
                            }
                            PropertyAction {
                                target: pageLoader
                                property: "anchors.topMargin"
                                value: 20
                            }
                        }
                        ParallelAnimation {
                            NumberAnimation {
                                target: pageLoader
                                properties: "opacity"
                                from: 0
                                to: 1
                                duration: 200
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                            }
                            NumberAnimation {
                                target: pageLoader
                                properties: "anchors.topMargin"
                                to: 0
                                duration: 200
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                            }
                        }
                    }
                }
            }
        }
    }
}
