pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Stores user-added binaries/applications (native, .AppImage, .exe, ...) in a
 * dedicated JSON file at ~/.local/state/quickshell/user/customApps.json.
 * Handles launch routing: .exe goes through portproton (preferred) or wine,
 * everything else is exec'd directly.
 */
Singleton {
    id: root

    // Same location ii-eve's shell used (Directories.state exists on both shells), so
    // existing custom apps carry over and it works on shells lacking customAppsPath.
    property string filePath: FileUtils.trimFileProtocol(`${Directories.state}/user/customApps.json`)
    property string iconCacheDir: FileUtils.trimFileProtocol(`${Directories.cache}/customApps/icons`)
    // Bundled script, resolved relative to this file — not the host shell's scripts dir.
    property string exeIconScript: FileUtils.trimFileProtocol(Qt.resolvedUrl("../scripts/icons/extract-exe-icon-venv.sh"))
    property alias entries: customAppsAdapter.entries
    property alias dirs: customAppsAdapter.dirs
    property alias folders: customAppsAdapter.folders
    property bool ready: false
    // Set to true while a multi-write transaction is in flight (e.g.
    // removeAppAt, which has to update entries and folders together).
    // Folder-derived readers should bail out quickly during the window.
    property bool _suspendDerivedReads: false

    property bool winePresent: false
    property bool portprotonPresent: false

    readonly property var binaryExtensions: [
        "appimage", "exe", "sh", "bash", "zsh", "fish",
        "bin", "run", "py", "pl", "rb", "lua", "js",
        "x86_64", "x86_32", "x86", "arm64", "aarch64",
        "love", "jar"
    ]

    readonly property var binaryDirPrefixes: [
        "/usr/bin/", "/usr/local/bin/", "/usr/sbin/",
        "/bin/", "/sbin/", "/opt/"
    ]

    signal changed()
    signal addRejected(string reason)

    Process {
        running: true
        command: ["bash", "-c", "command -v wine"]
        onExited: (exitCode, exitStatus) => {
            root.winePresent = (exitCode === 0)
        }
    }

    Process {
        running: true
        command: ["bash", "-c", "command -v portproton"]
        onExited: (exitCode, exitStatus) => {
            root.portprotonPresent = (exitCode === 0)
        }
    }

    Process {
        running: true
        command: ["mkdir", "-p", root.iconCacheDir]
    }

    property var _iconQueue: []
    property var _currentIconTask: null

    Process {
        id: iconExtractor
        stdout: StdioCollector {
            id: iconExtractorOut
        }
        onExited: (exitCode, exitStatus) => {
            const task = root._currentIconTask
            root._currentIconTask = null
            if (task && exitCode === 0) {
                root._applyExtractedIcon(task.targetPath || task.exePath, task.outPath)
            }
            root._processIconQueue()
        }
    }

    property var _siblingQueue: []
    property var _currentSiblingTask: null

    Process {
        id: siblingExeFinder
        stdout: StdioCollector {
            id: siblingExeFinderOut
        }
        onExited: (exitCode, exitStatus) => {
            const task = root._currentSiblingTask
            root._currentSiblingTask = null
            if (task && exitCode === 0) {
                const found = String(siblingExeFinderOut.text || "").trim()
                if (found.length > 0) {
                    root._enqueueExeIcon(found, root._exeIconCachePath(found), task.scriptPath)
                }
            }
            root._processSiblingQueue()
        }
    }

    function _hashPath(path) {
        let h = 5381
        const s = String(path)
        for (let i = 0; i < s.length; i++) {
            h = ((h << 5) + h + s.charCodeAt(i)) | 0
        }
        return (h >>> 0).toString(16)
    }

    function _exeIconCachePath(exePath) {
        return `${root.iconCacheDir}/${root._hashPath(exePath)}.png`
    }

    function _processIconQueue() {
        if (root._currentIconTask) return
        if (root._iconQueue.length === 0) return
        const task = root._iconQueue.shift()
        root._currentIconTask = task
        iconExtractor.command = ["bash", root.exeIconScript, task.exePath, task.outPath]
        iconExtractor.running = true
    }

    function _enqueueExeIcon(exePath, outPath, targetPath) {
        root._iconQueue.push({
            exePath: exePath,
            outPath: outPath,
            targetPath: targetPath || exePath
        })
        root._processIconQueue()
    }

    function _applyExtractedIcon(targetPath, iconPath) {
        const idx = root.indexOfPath(targetPath)
        if (idx < 0) return
        const next = Array.from(root.entries)
        const updated = Object.assign({}, next[idx])
        updated.icon = iconPath
        next[idx] = updated
        customAppsAdapter.entries = next
        root.changed()
    }

    function _processSiblingQueue() {
        if (root._currentSiblingTask) return
        if (root._siblingQueue.length === 0) return
        const task = root._siblingQueue.shift()
        root._currentSiblingTask = task
        // Prefer a same-stem .exe, otherwise any .exe in the same directory.
        const script = 'p="$1"; d="$(dirname "$p")"; b="$(basename "$p")"; s="${b%.*}";' +
            ' if [ -f "$d/$s.exe" ]; then printf %s "$d/$s.exe"; exit 0; fi;' +
            ' find "$d" -maxdepth 1 -type f -iname "*.exe" 2>/dev/null | head -n1'
        siblingExeFinder.command = ["bash", "-c", script, "_", task.scriptPath]
        siblingExeFinder.running = true
    }

    function _enqueueSiblingExeLookup(scriptPath) {
        root._siblingQueue.push({ scriptPath: scriptPath })
        root._processSiblingQueue()
    }

    function _upgradeExeIcons() {
        for (let i = 0; i < root.entries.length; i++) {
            const e = root.entries[i]
            if (!e || !e.path) continue
            if (!String(e.path).toLowerCase().endsWith('.exe')) continue
            if (e.icon && String(e.icon).startsWith('/')) continue
            root._enqueueExeIcon(e.path, root._exeIconCachePath(e.path))
        }
    }

    function _upgradeScriptIcons() {
        const next = Array.from(root.entries)
        let changed = false
        for (let i = 0; i < next.length; i++) {
            const e = next[i]
            if (!e || !e.path) continue
            if (String(e.path).toLowerCase().endsWith('.exe')) continue
            if (e.icon && String(e.icon).startsWith('/')) continue
            // Re-evaluate with the new conservative logic. Old fuzzy-match
            // garbage gets overwritten; legitimate icon names stay.
            const conservative = root.guessIconFor(e.path)
            if (e.icon !== conservative) {
                const updated = Object.assign({}, e)
                updated.icon = conservative
                next[i] = updated
                changed = true
            }
            if (conservative === "application-x-executable") {
                root._enqueueSiblingExeLookup(e.path)
            }
        }
        if (changed) {
            customAppsAdapter.entries = next
            root.changed()
        }
    }

    onReadyChanged: if (root.ready) {
        root._upgradeExeIcons()
        root._upgradeScriptIcons()
    }

    function indexOfPath(path) {
        const trimmed = FileUtils.trimFileProtocol(path)
        for (let i = 0; i < root.entries.length; i++) {
            if (root.entries[i].path === trimmed) return i
        }
        return -1
    }

    function isLikelyBinary(path) {
        if (!path) return false
        const s = String(path)
        const basename = s.split('/').pop()
        if (basename.length === 0) return false
        const dot = basename.lastIndexOf('.')
        if (dot === 0) return false
        if (dot < 0) {
            for (let i = 0; i < root.binaryDirPrefixes.length; i++) {
                if (s.startsWith(root.binaryDirPrefixes[i])) return true
            }
            return false
        }
        const ext = basename.substring(dot + 1).toLowerCase()
        return root.binaryExtensions.indexOf(ext) >= 0
    }

    function addApp(filePath) {
        const path = FileUtils.trimFileProtocol(filePath)
        if (!path || path.length === 0) return false
        if (root.indexOfPath(path) !== -1) return false
        if (!root.isLikelyBinary(path)) {
            console.warn("[CustomApps] rejected non-binary:", path)
            root.addRejected(path)
            return false
        }

        const basename = path.split('/').pop()
        const _dot = basename.lastIndexOf('.')
        const name = (_dot > 0) ? basename.substring(0, _dot) : basename
        const icon = root.guessIconFor(path)

        const next = Array.from(root.entries)
        next.push({ name: name, path: path, icon: icon })
        customAppsAdapter.entries = next
        root.changed()

        if (path.toLowerCase().endsWith('.exe')) {
            root._enqueueExeIcon(path, root._exeIconCachePath(path))
        } else if (icon === "application-x-executable") {
            root._enqueueSiblingExeLookup(path)
        }
        return true
    }

    function indexOfDir(dirPath) {
        const trimmed = FileUtils.trimFileProtocol(dirPath)
        for (let i = 0; i < root.dirs.length; i++) {
            if (root.dirs[i] === trimmed) return i
        }
        return -1
    }

    function addDir(dirPath) {
        const path = FileUtils.trimFileProtocol(dirPath)
        if (!path || path.length === 0) return false
        if (root.indexOfDir(path) !== -1) return false
        const next = Array.from(root.dirs)
        next.push(path)
        customAppsAdapter.dirs = next
        return true
    }

    function removeDirAt(index) {
        if (index < 0 || index >= root.dirs.length) return false
        const next = Array.from(root.dirs)
        next.splice(index, 1)
        customAppsAdapter.dirs = next
        return true
    }

    function removeAppAt(index) {
        if (index < 0 || index >= root.entries.length) return false

        // Build both shrunken `entries` and re-indexed `folders` before
        // touching the adapter so consumers (appsInFolder, gridModel) never
        // observe an intermediate state where `entries` has been spliced
        // but `folders.appIndices` still reference pre-splice positions —
        // that briefly displays the wrong app under each folder slot.
        const nextEntries = Array.from(root.entries)
        nextEntries.splice(index, 1)

        const nextFolders = Array.from(root.folders)
        for (let i = 0; i < nextFolders.length; i++) {
            const f = Object.assign({}, nextFolders[i])
            const appIndices = Array.from(f.appIndices || [])
            const patched = []
            for (let j = 0; j < appIndices.length; j++) {
                const v = appIndices[j]
                if (v === index) continue
                patched.push(v > index ? v - 1 : v)
            }
            f.appIndices = patched
            nextFolders[i] = f
        }

        // Suspend derived reads across both writes so any binding that
        // re-evaluates between the two assignments returns an empty/safe
        // value rather than mismatched (entries, folders).
        root._suspendDerivedReads = true
        customAppsAdapter.entries = nextEntries
        customAppsAdapter.folders = nextFolders
        root._suspendDerivedReads = false

        root.changed()
        return true
    }

    function _folderIndexOfId(id) {
        for (let i = 0; i < root.folders.length; i++) {
            if (root.folders[i].id === id) return i
        }
        return -1
    }

    function folderById(id) {
        const i = root._folderIndexOfId(id)
        return i >= 0 ? root.folders[i] : null
    }

    function createFolder(name) {
        const trimmed = String(name || "").trim()
        if (trimmed.length === 0) return ""
        const id = "folder_" + Date.now() + "_" + Math.floor(Math.random() * 10000)
        const next = Array.from(root.folders)
        next.push({ id: id, name: trimmed, icon: "folder", appIndices: [] })
        customAppsAdapter.folders = next
        root.changed()
        return id
    }

    function createDefaultFolder() {
        const base = "New folder"
        let name = base
        let counter = 1
        while (true) {
            let exists = false
            for (let i = 0; i < root.folders.length; i++) {
                if (root.folders[i].name === name) { exists = true; break }
            }
            if (!exists) break
            name = base + "(" + counter + ")"
            counter++
        }
        return root.createFolder(name)
    }

    function removeFolderAt(index) {
        if (index < 0 || index >= root.folders.length) return false
        const next = Array.from(root.folders)
        next.splice(index, 1)
        customAppsAdapter.folders = next
        root.changed()
        return true
    }

    function moveFolder(fromIdx, toIdx) {
        if (fromIdx < 0 || fromIdx >= root.folders.length) return false
        if (toIdx < 0 || toIdx >= root.folders.length) return false
        if (fromIdx === toIdx) return false
        const next = Array.from(root.folders)
        const [item] = next.splice(fromIdx, 1)
        next.splice(toIdx, 0, item)
        customAppsAdapter.folders = next
        root.changed()
        return true
    }

    function moveAppInEntries(fromIdx, toIdx) {
        if (fromIdx < 0 || fromIdx >= root.entries.length) return false
        if (toIdx < 0 || toIdx >= root.entries.length) return false
        if (fromIdx === toIdx) return false
        if (root._isEntryInAnyFolder(fromIdx)) {
            console.warn("[CustomApps] moveAppInEntries called on a foldered index; refusing")
            return false
        }

        const nextEntries = Array.from(root.entries)
        const [item] = nextEntries.splice(fromIdx, 1)
        nextEntries.splice(toIdx, 0, item)

        // The moved entry lives in the root by invariant, so its own index
        // does not appear in any folder's appIndices — we only need to shift
        // the other indices that fall in the [lo, hi] range.
        const lo = Math.min(fromIdx, toIdx)
        const hi = Math.max(fromIdx, toIdx)
        const dir = (fromIdx < toIdx) ? -1 : +1
        const nextFolders = Array.from(root.folders)
        for (let i = 0; i < nextFolders.length; i++) {
            const f = Object.assign({}, nextFolders[i])
            const arr = Array.from(f.appIndices || [])
            for (let j = 0; j < arr.length; j++) {
                const v = arr[j]
                if (v >= lo && v <= hi) arr[j] = v + dir
            }
            f.appIndices = arr
            nextFolders[i] = f
        }

        customAppsAdapter.entries = nextEntries
        customAppsAdapter.folders = nextFolders
        root.changed()
        return true
    }

    function renameFolder(folderId, newName) {
        const fi = root._folderIndexOfId(folderId)
        if (fi < 0) return false
        const trimmed = String(newName || "").trim()
        if (trimmed.length === 0) return false
        const next = Array.from(root.folders)
        const f = Object.assign({}, next[fi])
        f.name = trimmed
        next[fi] = f
        customAppsAdapter.folders = next
        root.changed()
        return true
    }

    function setFolderGpu(folderId, gpu) {
        const fi = root._folderIndexOfId(folderId)
        if (fi < 0) return false

        const nextFolders = Array.from(root.folders)
        const f = Object.assign({}, nextFolders[fi])
        if (gpu === "dGPU" || gpu === "iGPU") {
            f.gpu = gpu
        } else {
            delete f.gpu
        }
        nextFolders[fi] = f

        const nextEntries = Array.from(root.entries)
        const appIndices = f.appIndices || []
        for (let i = 0; i < appIndices.length; i++) {
            const idx = appIndices[i]
            if (idx < 0 || idx >= nextEntries.length) continue
            const e = Object.assign({}, nextEntries[idx])
            if (gpu === "dGPU" || gpu === "iGPU") {
                e.gpu = gpu
            } else {
                delete e.gpu
            }
            nextEntries[idx] = e
        }

        customAppsAdapter.folders = nextFolders
        customAppsAdapter.entries = nextEntries
        root.changed()
        return true
    }

    function renameAppAt(index, newName) {
        if (index < 0 || index >= root.entries.length) return false
        const trimmed = String(newName || "").trim()
        if (trimmed.length === 0) return false
        const next = Array.from(root.entries)
        const e = Object.assign({}, next[index])
        e.name = trimmed
        next[index] = e
        customAppsAdapter.entries = next
        root.changed()
        return true
    }

    function setEntryGpu(index, gpu) {
        if (index < 0 || index >= root.entries.length) return false
        const next = Array.from(root.entries)
        const e = Object.assign({}, next[index])
        if (gpu === "dGPU" || gpu === "iGPU") {
            e.gpu = gpu
        } else {
            delete e.gpu
        }
        next[index] = e
        customAppsAdapter.entries = next
        root.changed()
        return true
    }

    function addAppToFolder(folderId, entryIndex) {
        if (entryIndex < 0 || entryIndex >= root.entries.length) return false
        const nextFolders = Array.from(root.folders)
        let changed = false
        let targetFolder = null
        for (let i = 0; i < nextFolders.length; i++) {
            const f = Object.assign({}, nextFolders[i])
            const appIndices = Array.from(f.appIndices || [])
            const pos = appIndices.indexOf(entryIndex)
            if (f.id === folderId) {
                if (pos < 0) {
                    appIndices.push(entryIndex)
                    changed = true
                }
                targetFolder = f
            } else if (pos >= 0) {
                appIndices.splice(pos, 1)
                changed = true
            }
            f.appIndices = appIndices
            nextFolders[i] = f
        }
        if (!changed) return false

        customAppsAdapter.folders = nextFolders

        // Propagate folder's GPU pref to the newly added entry
        if (targetFolder && (targetFolder.gpu === "dGPU" || targetFolder.gpu === "iGPU")) {
            const nextEntries = Array.from(root.entries)
            const e = Object.assign({}, nextEntries[entryIndex])
            e.gpu = targetFolder.gpu
            nextEntries[entryIndex] = e
            customAppsAdapter.entries = nextEntries
        }

        root.changed()
        return true
    }

    function moveAppInFolder(folderId, fromPos, toPos) {
        const fi = root._folderIndexOfId(folderId)
        if (fi < 0) return false
        const folder = root.folders[fi]
        const appIndices = folder.appIndices || []
        if (fromPos < 0 || fromPos >= appIndices.length) return false
        if (toPos < 0 || toPos >= appIndices.length) return false
        if (fromPos === toPos) return false

        const newAppIndices = Array.from(appIndices)
        const [item] = newAppIndices.splice(fromPos, 1)
        newAppIndices.splice(toPos, 0, item)

        const nextFolders = Array.from(root.folders)
        const f = Object.assign({}, nextFolders[fi])
        f.appIndices = newAppIndices
        nextFolders[fi] = f
        customAppsAdapter.folders = nextFolders
        root.changed()
        return true
    }

    function removeAppFromFolder(folderId, entryIndex) {
        const fi = root._folderIndexOfId(folderId)
        if (fi < 0) return false
        const next = Array.from(root.folders)
        const f = Object.assign({}, next[fi])
        const appIndices = Array.from(f.appIndices || [])
        const pos = appIndices.indexOf(entryIndex)
        if (pos < 0) return false
        appIndices.splice(pos, 1)
        f.appIndices = appIndices
        next[fi] = f
        customAppsAdapter.folders = next
        root.changed()
        return true
    }

    function _isEntryInAnyFolder(entryIndex) {
        for (let i = 0; i < root.folders.length; i++) {
            const appIndices = root.folders[i].appIndices || []
            for (let j = 0; j < appIndices.length; j++) {
                if (appIndices[j] === entryIndex) return true
            }
        }
        return false
    }

    function rootEntriesList() {
        const out = []
        for (let i = 0; i < root.entries.length; i++) {
            if (root._isEntryInAnyFolder(i)) continue
            const e = root.entries[i]
            out.push({
                name: e.name,
                path: e.path,
                icon: e.icon,
                gpu: e.gpu,
                _originalIndex: i
            })
        }
        return out
    }

    readonly property var rootEntries: {
        root.entries
        root.folders
        return rootEntriesList()
    }

    function appsInFolder(folderId) {
        if (root._suspendDerivedReads) return []
        const fi = root._folderIndexOfId(folderId)
        if (fi < 0) return []
        const appIndices = root.folders[fi].appIndices || []
        const out = []
        for (let i = 0; i < appIndices.length; i++) {
            const idx = appIndices[i]
            if (idx < 0 || idx >= root.entries.length) continue
            const e = root.entries[idx]
            out.push({
                name: e.name,
                path: e.path,
                icon: e.icon,
                gpu: e.gpu,
                _originalIndex: idx
            })
        }
        return out
    }

    function folderPreviewIcons(folder, maxCount) {
        if (!folder) return []
        const indices = folder.appIndices || []
        const out = []
        const limit = Math.min(maxCount ?? 4, indices.length)
        for (let i = 0; i < limit; i++) {
            const idx = indices[i]
            if (idx < 0 || idx >= root.entries.length) continue
            out.push(root.entries[idx].icon || "")
        }
        return out
    }

    function guessIconFor(path) {
        const basename = path.split('/').pop()
        const _d = basename.lastIndexOf('.')
        const stem = (_d > 0) ? basename.substring(0, _d) : basename
        if (basename.toLowerCase().endsWith('.exe')) {
            if (AppSearch.iconExists(stem)) return stem
            const lower = stem.toLowerCase()
            if (AppSearch.iconExists(lower)) return lower
            return "wine"
        }
        // For scripts/native binaries we intentionally skip fuzzy matching —
        // it produces unrelated system icons for arbitrary script names.
        // A sibling .exe lookup will replace this with a real icon if possible.
        const entry = DesktopEntries.byId(stem)
        if (entry) return entry.icon
        if (AppSearch.iconExists(stem)) return stem
        const lower = stem.toLowerCase()
        if (AppSearch.iconExists(lower)) return lower
        const kebab = lower.replace(/\s+/g, "-")
        if (AppSearch.iconExists(kebab)) return kebab
        return "application-x-executable"
    }

    function shellQuote(s) {
        return `'${String(s).replace(/'/g, `'\\''`)}'`
    }

    // Cached parse of Persistent.states.appLauncher.launchParams.perAppJson.
    // Re-evaluates only when the JSON source string changes, so callers (this
    // service's launch path and the settings UI) can index it as a plain object.
    readonly property var perAppMap: {
        const lp = Persistent.states.appLauncher?.launchParams
        if (!lp) return ({})
        try { return JSON.parse(lp.perAppJson || "{}") } catch (e) { return ({}) }
    }

    readonly property var launchStatsMap: {
        const al = Persistent.states.appLauncher
        if (!al) return ({})
        try { return JSON.parse(al.launchStatsJson || "{}") } catch (e) { return ({}) }
    }

    function _writeLaunchStats(map) {
        const al = Persistent.states.appLauncher
        if (!al) return
        al.launchStatsJson = JSON.stringify(map)
    }

    function _recordLaunch(path) {
        if (!path) return
        const map = Object.assign({}, root.launchStatsMap)
        const cur = map[path] || { count: 0, last: 0 }
        map[path] = { count: (cur.count || 0) + 1, last: Date.now() }
        root._writeLaunchStats(map)
    }

    function _touchLast(path) {
        if (!path) return
        const map = Object.assign({}, root.launchStatsMap)
        const cur = map[path] || { count: 0, last: 0 }
        map[path] = { count: cur.count || 0, last: Date.now() }
        root._writeLaunchStats(map)
    }

    function _norm(s) {
        return String(s || "").trim().toLowerCase()
    }

    // Open Hyprland windows that belong to `path`. Uses the per-app matchClass
    // override when set, otherwise a heuristic from the basename stem + entry
    // name. A window matches when a candidate equals or is a substring of its
    // class / initialClass / title (all normalized).
    function runningWindowsForPath(path) {
        if (!path) return []
        const candidates = []
        const override = root.perAppMap[path]?.matchClass
        if (override && String(override).trim().length > 0) {
            candidates.push(root._norm(override))
        } else {
            const basename = String(path).split('/').pop()
            const _d = basename.lastIndexOf('.')
            const stem = (_d > 0) ? basename.substring(0, _d) : basename
            const ns = root._norm(stem)
            if (ns.length > 0) candidates.push(ns)
            const idx = root.indexOfPath(path)
            if (idx >= 0) {
                const nm = root._norm(root.entries[idx]?.name)
                if (nm.length > 0 && candidates.indexOf(nm) < 0) candidates.push(nm)
            }
        }
        if (candidates.length === 0) return []

        const out = []
        const wins = HyprlandData.windowList || []
        for (let i = 0; i < wins.length; i++) {
            const w = wins[i]
            const fields = [root._norm(w.class), root._norm(w.initialClass), root._norm(w.title)]
            let matched = false
            for (let c = 0; c < candidates.length && !matched; c++) {
                const cand = candidates[c]
                for (let f = 0; f < fields.length; f++) {
                    const fv = fields[f]
                    if (fv.length > 0 && (fv === cand || fv.indexOf(cand) >= 0)) { matched = true; break }
                }
            }
            if (matched) out.push(w)
        }
        return out
    }

    function isPathRunning(path) {
        return root.runningWindowsForPath(path).length > 0
    }

    // Focus an existing window if the app is already running, else launch.
    // Addresses in HyprlandData.windowList (hyprctl clients -j) already carry
    // the 0x prefix; same dispatch as Overview (OverviewWidget.qml:518).
    function activate(entry) {
        if (!entry || !entry.path) return
        const wins = root.runningWindowsForPath(entry.path)
        if (wins.length > 0) {
            Hyprland.dispatch(`hl.dsp.focus({window = "address:${wins[0].address}"})`)
            root._touchLast(entry.path)
            return
        }
        root.launch(entry)
    }

    function _statsEntriesList() {
        const map = root.launchStatsMap
        const out = []
        for (let i = 0; i < root.entries.length; i++) {
            const e = root.entries[i]
            if (!e || !e.path) continue
            const st = map[e.path]
            if (!st) continue
            out.push({
                name: e.name,
                path: e.path,
                icon: e.icon,
                gpu: e.gpu,
                _originalIndex: i,
                _count: st.count || 0,
                _last: st.last || 0
            })
        }
        return out
    }

    readonly property var recentApps: {
        root.entries
        root.launchStatsMap
        const arr = root._statsEntriesList()
        arr.sort((a, b) => b._last - a._last)
        return arr.slice(0, 12)
    }

    readonly property var frequentApps: {
        root.entries
        root.launchStatsMap
        const arr = root._statsEntriesList()
        arr.sort((a, b) => b._count - a._count)
        return arr.slice(0, 12)
    }

    // Builds the wrapper-prefix that prepends `path` in the bash invocation
    // assembled by launch().
    //
    // NOTE: defaultsExtra and per-app `params` are pasted verbatim into a
    // `bash -c` command line. This is intentional — users routinely need
    // shell features there (env-var expansions like `--data-dir "$HOME/x"`,
    // multiple flags, glob patterns). The trade-off is that any `;`, `&&`,
    // `` ` ``, `$(...)` in those fields *will* be interpreted by the shell.
    // Treat both fields as user-trusted shell input; never feed external /
    // untrusted text into them.
    function _buildLaunchPrefix(path) {
        const lp = Persistent.states.appLauncher?.launchParams
        if (!lp) return ""
        const entry = root.perAppMap[path] || null
        // Defaults apply to every native binary unless the user has explicitly
        // disabled them via a per-app entry with `useDefaults: false`.
        const useDefaults = entry ? entry.useDefaults !== false : true
        const local = entry ? String(entry.params || "").trim() : ""

        let defaults = ""
        if (useDefaults) {
            const segs = []
            // Wrapper order matches what works from a shell:
            //   `mangohud gamemoderun /path/to/game`
            // mangohud sets LD_PRELOAD then execs gamemoderun, which adds
            // libgamemodeauto and execs the game.
            if (lp.defaultsMangohud) {
                const cfg = String(lp.defaultsMangohudConfig || "").trim()
                if (lp.defaultsUseMangohudConfig && cfg.length > 0) {
                    segs.push(`MANGOHUD_CONFIG='${cfg.replace(/'/g, `'\\''`)}'`)
                }
                segs.push("mangohud")
            }
            if (lp.defaultsGamemoderun) segs.push("gamemoderun")
            const extra = String(lp.defaultsExtra || "").trim()
            if (extra.length > 0) segs.push(extra)
            defaults = segs.join(" ")
        }
        return [defaults, local].filter(s => s.length > 0).join(" ")
    }

    function launch(entry) {
        if (!entry || !entry.path) return
        const useDGpu = entry.gpu === "dGPU" && GpuInfo.hybrid
        const envList = useDGpu ? GpuInfo.dGpuEnv : []
        const envPrefix = envList.length > 0 ? ["env", ...envList] : []

        const path = entry.path
        const lower = path.toLowerCase()

        if (lower.endsWith('.exe')) {
            if (root.portprotonPresent) {
                Quickshell.execDetached({ command: [...envPrefix, "portproton", "--launch", path] })
                root._recordLaunch(path)
                return
            }
            if (root.winePresent) {
                Quickshell.execDetached({ command: [...envPrefix, "wine", path] })
                root._recordLaunch(path)
                return
            }
            console.warn("[CustomApps] cannot launch .exe: neither portproton nor wine is installed:", path)
            return
        }

        // Native binary / .AppImage / script — ensure +x, cd to the binary's
        // directory (Unity / .x86_64 games and .sh wrappers often expect
        // resources relative to cwd), then run with optional launch prefix.
        const prefix = root._buildLaunchPrefix(path)
        const quoted = root.shellQuote(path)
        const dir = root.shellQuote(path.substring(0, path.lastIndexOf('/')) || '/')
        const cmdBody = prefix.length > 0 ? `${prefix} ${quoted}` : `exec ${quoted}`
        Quickshell.execDetached({
            command: [...envPrefix, "bash", "-c",
                `chmod +x ${quoted} 2>/dev/null; cd ${dir} 2>/dev/null; ${cmdBody}`]
        })
        root._recordLaunch(path)
    }

    Timer { id: writeTimer; interval: 100; repeat: false; onTriggered: fileView.writeAdapter() }
    Timer { id: reloadTimer; interval: 100; repeat: false; onTriggered: fileView.reload() }

    FileView {
        id: fileView
        path: root.filePath
        watchChanges: true
        onFileChanged: reloadTimer.restart()
        onAdapterUpdated: writeTimer.restart()
        onLoaded: root.ready = true
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) writeTimer.restart()
        }

        adapter: JsonAdapter {
            id: customAppsAdapter
            property list<var> entries: []
            property list<string> dirs: []
            property list<var> folders: []
        }
    }
}
