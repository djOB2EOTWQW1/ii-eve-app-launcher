pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Detects hybrid-graphics configuration once at startup by parsing `lspci`.
 * Exposes `hybrid`, `dGpuVendor`, and `dGpuEnv` for use at app-launch time.
 *
 * Detection rule (covers the common cases):
 *   - NVIDIA present among GPUs  → dGpuVendor = "nvidia"
 *   - Else Intel + AMD present   → dGpuVendor = "amd"
 *   - Else                       → dGpuVendor = "",  hybrid = false
 *
 * Intel-dGPU configs (Intel Arc + Intel iGPU) are not detected — treated as
 * non-hybrid; disambiguating pure-Intel setups without PCI-class parsing is
 * out of scope.
 */
Singleton {
    id: root

    property bool ready: false
    property bool hybrid: false
    property string dGpuVendor: ""
    property var dGpuEnv: []

    Process {
        id: lspciProc
        running: true
        command: ["bash", "-c", "lspci -nn | grep -Ei 'VGA|3D|Display' || true"]
        stdout: StdioCollector {
            id: lspciOut
        }
        onExited: (exitCode, exitStatus) => {
            const text = String(lspciOut.text || "")
            root._parse(text)
            root.ready = true
        }
    }

    function _parse(text) {
        const lines = text.split("\n")
        let hasNvidia = false
        let hasAmd = false
        let hasIntel = false
        let count = 0
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i]
            if (line.trim().length === 0) continue
            count++
            const lower = line.toLowerCase()
            if (lower.indexOf("nvidia") >= 0) hasNvidia = true
            else if (lower.indexOf("amd") >= 0 || lower.indexOf("advanced micro devices") >= 0 || lower.indexOf("ati ") >= 0) hasAmd = true
            else if (lower.indexOf("intel") >= 0) hasIntel = true
        }

        if (count < 2) {
            root.hybrid = false
            root.dGpuVendor = ""
            root.dGpuEnv = []
            return
        }

        if (hasNvidia) {
            root.dGpuVendor = "nvidia"
            root.dGpuEnv = [
                "__NV_PRIME_RENDER_OFFLOAD=1",
                "__GLX_VENDOR_LIBRARY_NAME=nvidia",
                "__VK_LAYER_NV_optimus=NVIDIA_only"
            ]
            root.hybrid = true
            return
        }

        if (hasIntel && hasAmd) {
            root.dGpuVendor = "amd"
            root.dGpuEnv = ["DRI_PRIME=1"]
            root.hybrid = true
            return
        }

        root.hybrid = false
        root.dGpuVendor = ""
        root.dGpuEnv = []
    }
}
