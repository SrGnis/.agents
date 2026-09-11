#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/opencode"

command -v opencode &>/dev/null ||
    [[ -f "${CONFIG_DIR}/opencode.jsonc" || -f "${CONFIG_DIR}/opencode.json" ]]
