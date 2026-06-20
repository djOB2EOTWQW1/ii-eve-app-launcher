#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ILLOGICAL_IMPULSE_VIRTUAL_ENV is often not exported into the env QML hands to bash,
# so fall back to the shell's default uv venv location (same on ii-eve and ii-vynx).
VENV="$(eval echo "${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$HOME/.local/state/quickshell/.venv}")"
source "$VENV/bin/activate"
"$SCRIPT_DIR/extract_exe_icon.py" "$@"
status=$?
deactivate
exit $status
