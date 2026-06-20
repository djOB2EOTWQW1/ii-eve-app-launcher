// Vimium-style hint generator and prefix matcher shared by the launcher,
// its settings overlay and the folder viewer.

function generateHints(count) {
    const chars = "ASDFGHJKLQWERTYUIOP"
    const n = chars.length
    const hints = []
    if (count <= n) {
        for (let i = 0; i < count; i++) hints.push(chars[i])
    } else if (count <= n * n) {
        for (let i = 0; i < count; i++)
            hints.push(chars[Math.floor(i / n)] + chars[i % n])
    } else {
        for (let i = 0; i < count; i++) {
            hints.push(chars[Math.floor(i / (n * n))]
                + chars[Math.floor(i / n) % n]
                + chars[i % n])
        }
    }
    return hints
}

// Classifies `typed` against the hint list.
//   action === "none"   — wait for more input (or typed is empty)
//   action === "reset"  — no hint can match; caller should clear typed
//   action === "commit" — typed exactly matches hint at `index`
function matchTyped(hints, typed) {
    if (!typed || typed.length === 0) return { action: "none" }
    let exact = -1
    let hasPrefix = false
    for (let i = 0; i < hints.length; i++) {
        if (hints[i] === typed) exact = i
        else if (hints[i].startsWith(typed)) hasPrefix = true
    }
    if (exact < 0 && !hasPrefix) return { action: "reset" }
    if (exact >= 0 && !hasPrefix) return { action: "commit", index: exact }
    return { action: "none" }
}
