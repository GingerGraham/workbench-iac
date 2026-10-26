#!/usr/bin/env bash
# tests/check-ansible-vault.sh — workbench-iac
# ansible-vault-decrypt / ansible-vault-encrypt parse -p on every call, not
# just the first: getopts' OPTIND is global unless the function makes it
# local, so a second call in the same shell skipped -p and ignored the vault
# password file. Runs in bash and, when installed, zsh (shell/ansible.sh is
# sourced into both). ansible and ansible-vault are stubs. Plain bash,
# numbered OK:/FAIL: checks, matching workbench-core's tests/check-*.sh
# convention.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# `command -v ansible` must pass for shell/ansible.sh to define anything.
mkdir -p "${WORK}/bin" "${WORK}/project"
printf '#!/bin/sh\nexit 0\n' > "${WORK}/bin/ansible"
chmod +x "${WORK}/bin/ansible"
: > "${WORK}/project/vault-pass"

# The same script in either shell: source the module file, then call each
# function twice with -p. ansible-vault prints its arguments.
cat > "${WORK}/driver.sh" <<'DRIVER'
log_error() { echo "ERROR: $*"; }
log_warn()  { echo "WARN: $*"; }
_wb_declare_availability() { :; }
ansible-vault() { echo "VAULT: $*"; }
. "${MODULE_FILE}"
cd "${PROJECT_DIR}" || exit 1
for fn in ansible-vault-decrypt ansible-vault-encrypt; do
    "${fn}" -p vault-pass first.yml
    "${fn}" -p vault-pass second.yml
done
DRIVER

# check_shell <bash|zsh> <command...>
check_shell() {
    local name="$1"; shift
    local out
    out="$(PATH="${WORK}/bin:${PATH}" MODULE_FILE="${REPO_ROOT}/shell/ansible.sh" \
        PROJECT_DIR="${WORK}/project" "$@" "${WORK}/driver.sh" 2>&1)"
    local action
    for action in decrypt encrypt; do
        if [[ "${out}" == *"VAULT: ${action} --vault-password-file vault-pass first.yml"* ]]; then
            ok "${name}: ansible-vault-${action} honours -p on the first call"
        else
            fail "${name}: ansible-vault-${action} first call: ${out}"
        fi
        if [[ "${out}" == *"VAULT: ${action} --vault-password-file vault-pass second.yml"* ]]; then
            ok "${name}: ansible-vault-${action} honours -p on a second call in the same shell"
        else
            fail "${name}: ansible-vault-${action} second call: ${out}"
        fi
    done
}

check_shell bash bash
if command -v zsh >/dev/null 2>&1; then
    check_shell zsh zsh -f
else
    echo "SKIP: zsh not installed — zsh checks not run"
fi

echo
echo "==============================="
echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
echo "==============================="
exit "${FAILED}"
