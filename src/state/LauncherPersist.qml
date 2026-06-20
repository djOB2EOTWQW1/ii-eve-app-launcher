pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

// Persistent launcher settings, bundled so they save on shells whose Persistent has no
// appLauncher subtree (e.g. ii-vynx). Mirrors the fields ii-eve kept under
// LauncherPersist. Stored in its own file next to the shell's states.
Singleton {
    id: root

    property string filePath: `${Directories.state}/user/appLauncherExt.json`

    property alias iconSize: adapter.iconSize
    property alias windowSize: adapter.windowSize
    property alias launchStatsJson: adapter.launchStatsJson
    property alias recentsMode: adapter.recentsMode
    property alias launchParams: adapter.launchParams

    Timer { id: writeTimer; interval: 100; onTriggered: fileView.writeAdapter() }
    Timer { id: reloadTimer; interval: 100; onTriggered: fileView.reload() }

    FileView {
        id: fileView
        path: root.filePath
        watchChanges: true
        onFileChanged: reloadTimer.restart()
        onAdapterUpdated: writeTimer.restart()
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) writeTimer.restart()
        }

        adapter: JsonAdapter {
            id: adapter
            property int iconSize: 64
            property string windowSize: "settings"
            property string launchStatsJson: "{}"
            property string recentsMode: "recent"

            property JsonObject launchParams: JsonObject {
                property bool defaultsMangohud: false
                property bool defaultsGamemoderun: false
                property string defaultsExtra: ""
                property bool defaultsUseMangohudConfig: false
                property string defaultsMangohudConfig: ""
                property string perAppJson: "{}"
            }
        }
    }
}
