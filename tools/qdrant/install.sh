#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$1"
TOOL_DIR="${SCRIPT_DIR}/tools/qdrant"
SKILLS_DIR="${SCRIPT_DIR}/skills"

log_info()    { printf "\033[34m[INFO]\033[0m %s\n" "$1"; }
log_error()   { printf "\033[31m[ERROR]\033[0m %s\n" "$1"; }
log_success() { printf "\033[32m[OK]\033[0m %s\n" "$1"; }

check_deps() {
    if ! command -v docker &>/dev/null; then
        log_error "Required command 'docker' not found"
        return 1
    fi
}

ensure_uv() {
    if command -v uvx &>/dev/null; then
        return 0
    fi
    log_info "Installing uv (Python package manager)..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    if ! command -v uvx &>/dev/null; then
        log_error "Failed to install uv. Install manually: https://docs.astral.sh/uv/"
        return 1
    fi
    log_success "uv installed"
}

ensure_env() {
    if [[ ! -f "${TOOL_DIR}/.env" ]]; then
        log_info "Creating .env from .env.example"
        cp "${TOOL_DIR}/.env.example" "${TOOL_DIR}/.env"
    fi
}

setup_venv() {
    local venv_dir="${TOOL_DIR}/.venv"
    if [[ ! -d "$venv_dir" ]]; then
        log_info "Installing Python 3.12 (tree-sitter-languages requires <=3.12)..."
        uv python install 3.12
        log_info "Creating Python virtual environment..."
        uv venv --python 3.12 "$venv_dir"
        log_success "Virtual environment created"
    fi
    log_info "Installing indexer dependencies..."
    uv pip install --python "$venv_dir/bin/python" \
        "tree-sitter>=0.21,<0.22" tree-sitter-languages "qdrant-client[fastembed]"
    log_success "Indexer dependencies installed"
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

enable_qdrant() {
    check_deps
    ensure_uv
    ensure_env
    setup_venv

    log_info "Starting Qdrant container..."
    docker compose -f "${TOOL_DIR}/docker-compose.yml" up -d
    log_success "Qdrant container started"

    discover_harnesses
    select_harnesses
    configure_harnesses

    mkdir -p "${SKILLS_DIR}/qdrant"
    ln -sfn "../../tools/qdrant/SKILL.md" "${SKILLS_DIR}/qdrant/SKILL.md"
    log_success "Skill symlink created"

    log_success "Qdrant installed. Run /index in a repo to enable code indexing."
}

enable_qdrant
