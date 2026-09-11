#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$1"
TOOL_DIR="${SCRIPT_DIR}/tools/searxng"
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
}

ensure_settings() {
    local settings="${TOOL_DIR}/core-config/settings.yml"
    if [[ ! -f "${settings}" ]]; then
        log_info "Creating core-config/settings.yml from .example"
        cp "${settings}.example" "${settings}"
    fi

    if grep -qF '6JFiSWym4LzVU2ya7NJNa7puKYrk' "${settings}"; then
        local key
        key="$(openssl rand -hex 16)"
        sed -i "s|secret_key: \".*\"|secret_key: \"${key}\"|" "${settings}"
        log_success "Generated SearXNG secret_key"
    fi
}

enable_searxng() {
    check_deps
    ensure_env
    ensure_settings
    source "${TOOL_DIR}/.env"

    log_info "Starting SearXNG containers..."
    docker compose -f "${TOOL_DIR}/docker-compose.yml" up -d
    log_success "SearXNG containers started"

    log_info "Installing mcp-searxng..."
    pnpm install -g mcp-searxng
    log_success "mcp-searxng installed"

    discover_harnesses
    select_harnesses
    configure_harnesses

    mkdir -p "${SKILLS_DIR}/searxng"
    ln -sf "${TOOL_DIR}/SKILL.md" "${SKILLS_DIR}/searxng/SKILL.md"
    log_success "Skill symlink created"
}

enable_searxng
