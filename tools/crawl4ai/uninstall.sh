#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$1"
TOOL_DIR="${SCRIPT_DIR}/tools/crawl4ai"
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

disable_crawl4ai() {
    source "${TOOL_DIR}/.env"
    remove_harness_integrations

    log_info "Stopping Crawl4AI container..."
    docker compose -f "${TOOL_DIR}/docker-compose.yml" down 2>/dev/null ||
        log_error "Failed to stop container (may not be running)"

    log_info "Uninstalling crawl4ai-mcp-sse-stdio..."
    pnpm uninstall -g crawl4ai-mcp-sse-stdio 2>/dev/null ||
        log_error "Failed to uninstall crawl4ai-mcp-sse-stdio (may not be installed)"

    rm -f "${SKILLS_DIR}/crawl4ai/SKILL.md"
    rmdir "${SKILLS_DIR}/crawl4ai" 2>/dev/null || true
    log_success "Skill symlink removed"
}

disable_crawl4ai
