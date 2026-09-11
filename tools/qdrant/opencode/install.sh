#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$1"
TOOL_DIR="${SCRIPT_DIR}/tools/qdrant"

printf '\033[34m[INFO]\033[0m Qdrant is configured per-project. Run /index inside a repo to enable indexing.\n'

