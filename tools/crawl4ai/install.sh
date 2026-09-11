#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$1"
TOOL_DIR="${SCRIPT_DIR}/tools/crawl4ai"
SKILLS_DIR="${SCRIPT_DIR}/skills"

log_info()    { printf "\033[34m[INFO]\033[0m %s\n" "$1"; }
log_error()   { printf "\033[31m[ERROR]\033[0m %s\n" "$1"; }
log_success() { printf "\033[32m[OK]\033[0m %s\n" "$1"; }

check_deps() {
    for cmd in docker pnpm; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command '${cmd}' not found"
            return 1
        fi
    done
}

discover_harnesses() {
    local adapter_dir harness
    DETECTED_HARNESSES=()

    shopt -s nullglob
    for adapter_dir in "${TOOL_DIR}"/*/; do
        harness="$(basename "${adapter_dir%/}")"
        [[ -x "${adapter_dir}/detect.sh" ]] || continue
        if bash "${adapter_dir}/detect.sh" "${SCRIPT_DIR}"; then
            DETECTED_HARNESSES+=("${harness}")
        fi
    done
    shopt -u nullglob
}

select_harnesses() {
    SELECTED_HARNESSES=()
    ((${#DETECTED_HARNESSES[@]} > 0)) || return 0

    printf "Detected harnesses:\n"
    local index harness selection item valid
    for index in "${!DETECTED_HARNESSES[@]}"; do
        printf "  %d. %s\n" "$((index + 1))" "${DETECTED_HARNESSES[index]}"
    done

    if [[ ! -t 0 ]]; then
        selection=""
    else
        read -r -p "Select harnesses (comma-separated, blank for all): " selection
    fi

    if [[ -z "${selection}" ]]; then
        SELECTED_HARNESSES=("${DETECTED_HARNESSES[@]}")
        return 0
    fi

    IFS=',' read -ra items <<< "${selection}"
    for item in "${items[@]}"; do
        item="${item//[[:space:]]/}"
        valid=false
        if [[ "${item}" =~ ^[0-9]+$ ]] &&
            ((item >= 1 && item <= ${#DETECTED_HARNESSES[@]})); then
            harness="${DETECTED_HARNESSES[item - 1]}"
            valid=true
        else
            for harness in "${DETECTED_HARNESSES[@]}"; do
                [[ "${item}" == "${harness}" ]] || continue
                valid=true
                break
            done
        fi
        if [[ "${valid}" == true ]]; then
            [[ " ${SELECTED_HARNESSES[*]} " == *" ${harness} "* ]] ||
                SELECTED_HARNESSES+=("${harness}")
        else
            log_error "Unknown harness selection: ${item}"
            return 1
        fi
    done
}

configure_harnesses() {
    local harness
    for harness in "${SELECTED_HARNESSES[@]}"; do
        log_info "Configuring ${harness}..."
        bash "${TOOL_DIR}/${harness}/install.sh" "${SCRIPT_DIR}"
    done
}

ensure_env() {
    if [[ ! -f "${TOOL_DIR}/.env" ]]; then
        log_info "Creating .env from .env.example"
        cp "${TOOL_DIR}/.env.example" "${TOOL_DIR}/.env"
    fi

    if ! grep -qE '^[[:space:]]*CRAWL4AI_API_TOKEN=.+' "${TOOL_DIR}/.env"; then
        local token
        token="$(openssl rand -hex 32)"
        if grep -qE '^[[:space:]]*CRAWL4AI_API_TOKEN=' "${TOOL_DIR}/.env"; then
            sed -i "s|^[[:space:]]*CRAWL4AI_API_TOKEN=.*|CRAWL4AI_API_TOKEN=${token}|" "${TOOL_DIR}/.env"
        else
            printf "\nCRAWL4AI_API_TOKEN=%s\n" "$token" >> "${TOOL_DIR}/.env"
        fi
        log_success "Generated CRAWL4AI_API_TOKEN"
    fi
}

enable_crawl4ai() {
    check_deps
    ensure_env
    source "${TOOL_DIR}/.env"

    log_info "Starting Crawl4AI container..."
    docker compose -f "${TOOL_DIR}/docker-compose.yml" up -d
    log_success "Crawl4AI container started"

    log_info "Installing crawl4ai-mcp-sse-stdio..."
    pnpm install -g crawl4ai-mcp-sse-stdio
    log_success "crawl4ai-mcp-sse-stdio installed"

    discover_harnesses
    select_harnesses
    configure_harnesses

    mkdir -p "${SKILLS_DIR}/crawl4ai"
    ln -sf "${TOOL_DIR}/SKILL.md" "${SKILLS_DIR}/crawl4ai/SKILL.md"
    log_success "Skill symlink created"
}

enable_crawl4ai
