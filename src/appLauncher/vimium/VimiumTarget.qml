import QtQuick

// A single Vimium hint badge that registers itself with a VimiumRegistry and
// carries its element's action inline via onActivated. Drop one next to any
// clickable element, at the same anchors a VimiumHintLabel would use.
VimiumHintLabel {
    id: target

    property var registry: null
    // Set false to exclude this element from hinting (e.g. hidden in a mode).
    property bool participates: true
    // Assigned by the registry during recompute; do not set manually.
    property string hint: ""

    signal activated()
    function activate() { target.activated() }

    hintText: target.hint
    typedText: target.registry?.typed ?? ""
    vimiumActive: target.registry?.active ?? false

    onRegistryChanged: if (target.registry) target.registry.register(target)
    onParticipatesChanged: if (target.registry) target.registry.revision++

    Component.onCompleted: if (target.registry) target.registry.register(target)
    Component.onDestruction: if (target.registry) target.registry.unregister(target)
}
