#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

log_info()    { printf "\033[34m[INFO]\033[0m %s\n" "$1"; }
log_error()   { printf "\033[31m[ERROR]\033[0m %s\n" "$1"; }
log_success() { printf "\033[32m[OK]\033[0m %s\n" "$1"; }

link_agents_md() {
    local config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/opencode"
    local target="${config_dir}/AGENTS.md"
    local source="${SCRIPT_DIR}/AGENTS.md"

    mkdir -p "${config_dir}"

    if [[ -L "${target}" ]]; then
        local current
        current="$(readlink -f "${target}")"
        if [[ "${current}" == "${source}" ]]; then
            log_info "AGENTS.md symlink already in place"
            return 0
        fi
        log_info "Replacing stale AGENTS.md symlink"
        rm "${target}"
    elif [[ -e "${target}" ]]; then
        log_info "Backing up existing AGENTS.md to AGENTS.md.bak"
        mv "${target}" "${target}.bak"
    fi

    ln -s "${source}" "${target}"
    log_success "Symlinked AGENTS.md → ${target}"
}

process_tool() {
    local tool="$1"
    local enabled="$2"
    local tool_dir="${SCRIPT_DIR}/tools/${tool}"

    if [[ ! -f "${tool_dir}/install.sh" ]] || [[ ! -f "${tool_dir}/uninstall.sh" ]]; then
        log_error "Tool '${tool}' missing install.sh or uninstall.sh"
        return 1
    fi

    if [[ "${enabled}" == "true" ]]; then
        log_info "Enabling ${tool}..."
        bash "${tool_dir}/install.sh" "${SCRIPT_DIR}"
        log_success "${tool} enabled"
    elif [[ "${enabled}" == "false" ]]; then
        log_info "Disabling ${tool}..."
        bash "${tool_dir}/uninstall.sh" "${SCRIPT_DIR}"
        log_success "${tool} disabled"
    else
        log_error "Invalid value for ${tool^^}_ENABLED: '${enabled}'"
        return 1
    fi
}

link_command() {
    local cmd="$1"
    local config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/opencode"
    local cmd_dir="${config_dir}/command"
    local source="${SCRIPT_DIR}/commands/${cmd}.md"

    [[ -f "$source" ]] || return 0
    mkdir -p "$cmd_dir"

    local target="${cmd_dir}/${cmd}.md"
    if [[ -L "${target}" ]]; then
        local current
        current="$(readlink -f "${target}")"
        if [[ "${current}" == "${source}" ]]; then
            log_info "Command '${cmd}' symlink already in place"
            return 0
        fi
        rm "${target}"
    elif [[ -e "${target}" ]]; then
        mv "${target}" "${target}.bak"
    fi

    ln -s "${source}" "${target}"
    log_success "Symlinked command '${cmd}' → ${target}"
}

link_agents() {
    local config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/opencode"
    local agent_dir="${config_dir}/agent"
    local source_dir="${SCRIPT_DIR}/agents"

    [[ -d "$source_dir" ]] || return 0
    mkdir -p "$agent_dir"

    local agent_file
    for agent_file in "$source_dir"/*.md; do
        [[ -f "$agent_file" ]] || continue
        local name
        name="$(basename "$agent_file")"
        local target="${agent_dir}/${name}"

        if [[ -L "${target}" ]]; then
            local current
            current="$(readlink -f "${target}")"
            if [[ "${current}" == "${agent_file}" ]]; then
                log_info "Agent '${name}' symlink already in place"
                continue
            fi
            rm "${target}"
        elif [[ -e "${target}" ]]; then
            mv "${target}" "${target}.bak"
        fi

        ln -s "${agent_file}" "${target}"
        log_success "Symlinked agent '${name}' → ${target}"
    done
}

main() {
    link_agents_md
    link_agents
    link_command "index"
    process_tool "searxng" "${SEARXNG_ENABLED:-false}"
    process_tool "crawl4ai" "${CRAWL4AI_ENABLED:-false}"
    process_tool "qdrant" "${QDRANT_ENABLED:-false}"
}

main "$@"
