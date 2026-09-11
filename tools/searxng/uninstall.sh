#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$1"
TOOL_DIR="${SCRIPT_DIR}/tools/searxng"
SKILLS_DIR="${SCRIPT_DIR}/skills"

log_info()    { printf "\033[34m[INFO]\033[0m %s\n" "$1"; }
log_error()   { printf "\033[31m[ERROR]\033[0m %s\n" "$1"; }
log_success() { printf "\033[32m[OK]\033[0m %s\n" "$1"; }

remove_harness_integrations() {
    local adapter_dir harness
    shopt -s nullglob
    for adapter_dir in "${TOOL_DIR}"/*/; do
        harness="$(basename "${adapter_dir%/}")"
        [[ -x "${adapter_dir}/detect.sh" ]] || continue
        if bash "${adapter_dir}/detect.sh" "${SCRIPT_DIR}"; then
            log_info "Removing ${harness} integration..."
            bash "${adapter_dir}/uninstall.sh" "${SCRIPT_DIR}"
        fi
    done
    shopt -u nullglob
}

disable_searxng() {
    source "${TOOL_DIR}/.env"
    remove_harness_integrations

    log_info "Stopping SearXNG containers..."
    docker compose -f "${TOOL_DIR}/docker-compose.yml" down 2>/dev/null ||
        log_error "Failed to stop containers (may not be running)"

    log_info "Uninstalling mcp-searxng..."
    pnpm uninstall -g mcp-searxng 2>/dev/null ||
        log_error "Failed to uninstall mcp-searxng (may not be installed)"

    rm -f "${SKILLS_DIR}/searxng/SKILL.md"
    rmdir "${SKILLS_DIR}/searxng" 2>/dev/null || true
    log_success "Skill symlink removed"
}

disable_searxng
