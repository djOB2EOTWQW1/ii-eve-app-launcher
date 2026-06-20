import QtQuick
import "LauncherVimium.js" as LV

// Per-surface Vimium registrar. Owns active/typed state, collects the
// VimiumTargets that registered with it, sorts them by on-screen position,
// assigns hint letters, and routes a committed hint to the matched target.
QtObject {
    id: registry

    property bool active: false
    property string typed: ""
    // Coordinate frame used for position sorting. May be null while the
    // owning surface's loader is inactive; sorting is skipped until set.
    property Item referenceItem: null

    // Registered VimiumTarget instances. Mutated only through register()/
    // unregister(), each of which bumps `revision` to trigger a recompute.
    property var _targets: []
    property int revision: 0

    // Sorted, participating targets after the last recompute. matchTyped reads
    // hint strings off these in order.
    property var _ordered: []

    function register(t) {
        if (!t) return
        const arr = registry._targets.slice()
        if (arr.indexOf(t) < 0) {
            arr.push(t)
            registry._targets = arr
            registry.revision++
        }
    }

    function unregister(t) {
        const arr = registry._targets.slice()
        const i = arr.indexOf(t)
        if (i >= 0) {
            arr.splice(i, 1)
            registry._targets = arr
            registry.revision++
        }
    }

    function _recompute() {
        const ref = registry.referenceItem
        const live = []
        for (let i = 0; i < registry._targets.length; i++) {
            const t = registry._targets[i]
            if (t && t.participates) live.push(t)
        }
        if (ref) {
            const rowTol = 20
            live.sort((a, b) => {
                const pa = a.mapToItem(ref, a.width / 2, a.height / 2)
                const pb = b.mapToItem(ref, b.width / 2, b.height / 2)
                if (Math.abs(pa.y - pb.y) > rowTol) return pa.y - pb.y
                return pa.x - pb.x
            })
        }
        const hints = LV.generateHints(live.length)
        for (let i = 0; i < live.length; i++) live[i].hint = hints[i] ?? ""
        for (let i = 0; i < registry._targets.length; i++) {
            const t = registry._targets[i]
            if (t && live.indexOf(t) < 0) t.hint = ""
        }
        registry._ordered = live
    }

    onRevisionChanged: Qt.callLater(registry._recompute)

    onActiveChanged: {
        if (registry.active) Qt.callLater(registry._recompute)
        else registry.typed = ""
    }

    onTypedChanged: {
        if (!registry.active) return
        const hints = registry._ordered.map(t => t.hint)
        const r = LV.matchTyped(hints, registry.typed)
        if (r.action === "reset") { registry.typed = ""; return }
        if (r.action !== "commit") return
        registry.active = false
        registry.typed = ""
        const t = registry._ordered[r.index]
        if (t) t.activate()
    }
}
