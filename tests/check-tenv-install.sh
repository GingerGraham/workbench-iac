#!/usr/bin/env bash
# tests/check-tenv-install.sh — workbench-iac
# Functional checks for the cosign gate in _tenv-install-rpm / _tenv-install-deb,
# with the download/verify step and the package managers stubbed. Plain bash,
# numbered OK:/FAIL: checks, matching workbench-core's tests/check-*.sh
# convention.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

# run_install <function> <cosign-verified: true|false>
# Runs the installer in a subshell and echoes its output; exits with its rc.
# Package managers are stubs that print "PKG: <argv>" so a call is visible.
run_install() {
    local func="$1" verified="$2"
    (
        export WORKBENCH_ARCH=x86_64
        # shellcheck disable=SC2329  # stubs, invoked by the sourced installers
        log_info()  { echo "INFO: $*"; }
        # shellcheck disable=SC2329
        log_error() { echo "ERROR: $*"; }
        # shellcheck disable=SC2329
        get-elevation-command() { echo ""; }
        # shellcheck disable=SC2329
        dnf()     { echo "PKG: dnf $*"; }
        # shellcheck disable=SC2329
        dpkg()    { echo "PKG: dpkg $*"; }
        # shellcheck disable=SC2329
        apt-get() { echo "PKG: apt-get $*"; }
        # shellcheck disable=SC1090,SC1091
        source "${REPO_ROOT}/shell/installers.sh"
        # Defined after sourcing: installers.sh defines the real one.
        # shellcheck disable=SC2329
        _tenv_fetch_and_verify() {
            _TENV_VERIFIED_ASSET="$1/tenv-asset"
            : > "${_TENV_VERIFIED_ASSET}"
            _TENV_COSIGN_VERIFIED="${verified}"
        }
        "${func}" v9.9.9 '{}'
    ) 2>&1
}

# 1-2. dnf path
out="$(run_install _tenv-install-rpm false)"; rc=$?
if [[ ${rc} -ne 0 && "${out}" == *"install-cosign"* && "${out}" != *"PKG:"* ]]; then
    ok "dnf path refuses without cosign verification and points at install-cosign"
else
    fail "dnf refusal (rc=${rc}): ${out}"
fi
out="$(run_install _tenv-install-rpm true)"; rc=$?
if [[ ${rc} -eq 0 && "${out}" == *"PKG: dnf install -y"* ]]; then
    ok "dnf path installs when cosign verified the asset"
else
    fail "dnf install (rc=${rc}): ${out}"
fi

# 3-4. apt/.deb path
out="$(run_install _tenv-install-deb false)"; rc=$?
if [[ ${rc} -ne 0 && "${out}" == *"install-cosign"* && "${out}" != *"PKG:"* ]]; then
    ok "apt (.deb) path refuses without cosign verification and points at install-cosign"
else
    fail "deb refusal (rc=${rc}): ${out}"
fi
out="$(run_install _tenv-install-deb true)"; rc=$?
if [[ ${rc} -eq 0 && "${out}" == *"PKG: dpkg -i"* ]]; then
    ok "apt (.deb) path installs when cosign verified the asset"
else
    fail "deb install (rc=${rc}): ${out}"
fi

echo
echo "==============================="
echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
echo "==============================="
exit "${FAILED}"
