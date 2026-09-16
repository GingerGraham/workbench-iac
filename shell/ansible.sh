#!/usr/bin/env bash
# shell/ansible.sh — workbench-iac
# Ansible tool configuration — aliases and vault helpers. Registered at
# tier: tools (.dotfiles-sync.yml), sourced unconditionally; self-guards on
# `command -v ansible`.
# Ported from workbench-precursor's tools/ansible.sh, unchanged.

# Function/alias availability predicates — consumed automatically by
# _get_functions_in/_get_aliases_in (workbench-core) to hide names that
# can't actually be used on this host. See workbench-core's
# docs/module-authoring.md, "Declaring function availability".
#
# Everything below is only ever defined once the `command -v ansible`
# guard passes, but get-iac-functions' static-grep listing can't see that
# runtime guard, so without this it would list ansible-vault-decrypt,
# ansible-vault-encrypt, ap, avd, and ave even on hosts without ansible.
# Declared here, ahead of the guard (unlike an early-return file, an
# if-wrapped one like this can't reach a declaration placed after the
# guard on a host where the guard fails), so the predicate is always
# defined regardless of whether ansible itself is present.
_wb_declare_availability ansible ansible-vault-decrypt ansible-vault-encrypt ap avd ave

# ── functions ─────────────────────────────────────────────────────────────────
if command -v ansible &>/dev/null; then
    ansible-vault-decrypt() {
        local VAULT_PASS="" FILES=()

        if ! command -v ansible &>/dev/null; then
            log_error "ansible is not installed"; return 1
        fi

        while getopts ":p:" opt; do
            case ${opt} in
                p) VAULT_PASS="${OPTARG}" ;;
                \?) log_error "Invalid option: -${OPTARG}"; return 1 ;;
            esac
        done
        shift $((OPTIND - 1))

        for arg in "$@"; do
            [[ ! "${arg}" =~ ^- ]] && FILES+=("${arg}")
        done

        if [[ ${#FILES[@]} -eq 0 ]]; then
            log_error "No files to decrypt"; return 1
        fi

        # Honour vault_password_file from ansible.cfg if present
        if [[ -f "ansible.cfg" ]] && grep -q "vault_password_file" "ansible.cfg"; then
            local cfg_vaultfile
            cfg_vaultfile="$(grep vault_password_file ansible.cfg | cut -d= -f2 | tr -d ' ')"
            if [[ -f "${cfg_vaultfile}" ]]; then
                for file in "${FILES[@]}"; do ansible-vault decrypt "${file}"; done
                return 0
            fi
        fi

        [[ -n "${VAULT_PASS}" && ! -f "${VAULT_PASS}" ]] && { log_warn "Vault pass file not found"; VAULT_PASS=""; }

        if [[ -n "${VAULT_PASS}" ]]; then
            for file in "${FILES[@]}"; do ansible-vault decrypt --vault-password-file "${VAULT_PASS}" "${file}"; done
        else
            for file in "${FILES[@]}"; do ansible-vault decrypt "${file}"; done
        fi
    }

    ansible-vault-encrypt() {
        local VAULT_PASS="" FILES=()

        if ! command -v ansible &>/dev/null; then
            log_error "ansible is not installed"; return 1
        fi

        while getopts ":p:" opt; do
            case ${opt} in
                p) VAULT_PASS="${OPTARG}" ;;
                \?) log_error "Invalid option: -${OPTARG}"; return 1 ;;
            esac
        done
        shift $((OPTIND - 1))

        for arg in "$@"; do
            [[ ! "${arg}" =~ ^- ]] && FILES+=("${arg}")
        done

        if [[ ${#FILES[@]} -eq 0 ]]; then
            log_error "No files to encrypt"; return 1
        fi

        if [[ -f "ansible.cfg" ]] && grep -q "vault_password_file" "ansible.cfg"; then
            local cfg_vaultfile
            cfg_vaultfile="$(grep vault_password_file ansible.cfg | cut -d= -f2 | tr -d ' ')"
            if [[ -f "${cfg_vaultfile}" ]]; then
                for file in "${FILES[@]}"; do ansible-vault encrypt "${file}"; done
                return 0
            fi
        fi

        [[ -n "${VAULT_PASS}" && ! -f "${VAULT_PASS}" ]] && { log_warn "Vault pass file not found"; VAULT_PASS=""; }

        if [[ -n "${VAULT_PASS}" ]]; then
            for file in "${FILES[@]}"; do ansible-vault encrypt --vault-password-file "${VAULT_PASS}" "${file}"; done
        else
            for file in "${FILES[@]}"; do ansible-vault encrypt "${file}"; done
        fi
    }

    # ── aliases ───────────────────────────────────────────────────────────────────
    # avd/ave alias to the wrapper functions above (not raw `ansible-vault
    # decrypt`/`encrypt`) so their vault_password_file/-p handling is actually
    # reached through the short alias.
    alias ap="ansible-playbook"
    alias avd="ansible-vault-decrypt"
    alias ave="ansible-vault-encrypt"
fi
