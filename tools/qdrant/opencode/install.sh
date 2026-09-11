#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$1"
TOOL_DIR="${SCRIPT_DIR}/tools/qdrant"

printf '\033[32m[OK]\033[0m Qdrant MCP configured per-project. Run /index in a repo to enable.\n'

