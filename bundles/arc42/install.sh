#!/usr/bin/env bash
set -euo pipefail

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="${BUNDLE_DIR}/skills"

MODE="copy"
FORCE=false
DRY_RUN=false
REMOVE=false
TARGET_ROOT=""

log_info()    { printf "\033[34m[INFO]\033[0m %s\n" "$1"; }
log_error()   { printf "\033[31m[ERROR]\033[0m %s\n" "$1" >&2; }
log_success() { printf "\033[32m[OK]\033[0m %s\n" "$1"; }

usage() {
    cat <<'EOF'
Install the optional arc42 skill bundle into a project.

Usage: install.sh [OPTIONS] [PROJECT_ROOT]

Options:
  --link      Symlink skills instead of copying (tracks ~/.agents updates)
  --force     Replace skills that already exist
  --remove    Remove the bundle from the project
  --dry-run   Show what would happen without changing anything
  -h, --help  Show this help

PROJECT_ROOT defaults to the current git root, or the current directory.
EOF
}

parse_args() {
    while (($# > 0)); do
        case "$1" in
            --link)    MODE="link" ;;
            --force)   FORCE=true ;;
            --remove)  REMOVE=true ;;
            --dry-run) DRY_RUN=true ;;
            -h|--help) usage; exit 0 ;;
            --*)       log_error "Unknown option: $1"; usage >&2; exit 1 ;;
            *)
                if [[ -n "${TARGET_ROOT}" ]]; then
                    log_error "Multiple project roots given"
                    exit 1
                fi
                TARGET_ROOT="$1"
                ;;
        esac
        shift
    done
}

resolve_root() {
    if [[ -n "${TARGET_ROOT}" ]]; then
        printf '%s\n' "${TARGET_ROOT}"
        return
    fi
    local git_root
    if git_root="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -n "${git_root}" ]]; then
        printf '%s\n' "${git_root}"
    else
        pwd
    fi
}

require_source() {
    if [[ ! -d "${SKILLS_SRC}" ]]; then
        log_error "Missing bundle skills directory: ${SKILLS_SRC}"
        exit 1
    fi
}

skill_names() {
    local src
    shopt -s nullglob
    for src in "${SKILLS_SRC}"/*/; do
        [[ -f "${src}SKILL.md" ]] || continue
        basename "${src%/}"
    done
    shopt -u nullglob
}

remove_skills() {
    local root="$1" skills_dir="${1}/.opencode/skills"
    local removed=() missing=()
    local name dest

    while IFS= read -r name; do
        dest="${skills_dir}/${name}"
        if [[ ! -e "${dest}" && ! -L "${dest}" ]]; then
            missing+=("${name}")
            continue
        fi
        if [[ "${DRY_RUN}" == true ]]; then
            log_info "Would remove ${name}"
        else
            rm -rf "${dest}"
            log_success "Removed ${name}"
        fi
        removed+=("${name}")
    done < <(skill_names)

    if [[ "${DRY_RUN}" != true ]]; then
        rmdir "${skills_dir}" 2>/dev/null || true
        rmdir "${root}/.opencode" 2>/dev/null || true
    fi

    printf '\n'
    log_info "Removed ${#removed[@]} skill(s) from ${skills_dir}; ${#missing[@]} not present."
}

install_skills() {
    local root="$1" skills_dir="${1}/.opencode/skills"
    local installed=() skipped=()
    local name src dest rel

    while IFS= read -r name; do
        src="${SKILLS_SRC}/${name}"
        dest="${skills_dir}/${name}"

        if [[ -e "${dest}" || -L "${dest}" ]]; then
            if [[ "${FORCE}" != true ]]; then
                log_info "Skipping ${name} (exists; use --force to replace)"
                skipped+=("${name}")
                continue
            fi
            [[ "${DRY_RUN}" == true ]] || rm -rf "${dest}"
        fi

        if [[ "${DRY_RUN}" == true ]]; then
            log_info "Would install ${name} (${MODE})"
        elif [[ "${MODE}" == "link" ]]; then
            mkdir -p "${skills_dir}"
            rel="$(realpath --relative-to="${skills_dir}" "${src}")"
            ln -s "${rel}" "${dest}"
            log_success "Linked ${name}"
        else
            mkdir -p "${skills_dir}"
            cp -R "${src}" "${dest}"
            log_success "Copied ${name}"
        fi
        installed+=("${name}")
    done < <(skill_names)

    printf '\n'
    log_info "Installed ${#installed[@]} skill(s) into ${skills_dir}; ${#skipped[@]} skipped."
    if [[ "${FORCE}" != true && ${#skipped[@]} -gt 0 ]]; then
        log_info "Use --force to replace skipped skills, or --link to track ~/.agents."
    fi
    if [[ "${DRY_RUN}" != true ]]; then
        log_info "Run /reload in OpenCode if the skills do not appear."
    fi
}

main() {
    parse_args "$@"
    require_source
    local root
    root="$(resolve_root)"

    if [[ ! -d "${root}" ]]; then
        log_error "Project root does not exist: ${root}"
        exit 1
    fi

    log_info "Project root: ${root}"
    if [[ "${REMOVE}" == true ]]; then
        remove_skills "${root}"
    else
        install_skills "${root}"
    fi
}

main "$@"
