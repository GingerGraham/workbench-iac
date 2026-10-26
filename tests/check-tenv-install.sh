#!/usr/bin/env bash
# shellcheck disable=SC2317  # shellcheck <0.10 reports the stubs below as unreachable (0.10+: SC2329, annotated at each site)
# tests/check-tenv-install.sh — workbench-iac
# Functional checks for the tenv installers: the cosign gate and tarball
# fallback in _tenv-install-rpm / _tenv-install-deb, the tarball's
# architecture, and the per-asset SHA-256 check in _tenv_fetch_and_verify.
# Downloads and package managers are stubbed; no network. Plain bash,
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

# run_install <function> <verify-result: true|false|fail> [env assignments...]
# Runs the installer in a subshell and echoes its output; exits with its rc.
# _tenv_fetch_and_verify is stubbed: "true" = cosign verified the asset,
# "false" = SHA-256 only (no cosign), "fail" = verification failed.
# Package managers are stubs that print "PKG: <argv>", and the tarball path
# prints "TARBALL: <argv>", so each call is visible.
run_install() {
    local func="$1" verified="$2"; shift 2
    (
        # shellcheck disable=SC2030  # per-run environment, deliberately subshell-local
        export WORKBENCH_ARCH=x86_64
        local kv
        for kv in "$@"; do export "${kv?}"; done
        # shellcheck disable=SC2329  # stubs, invoked by the sourced installers
        log_info()  { echo "INFO: $*"; }
        # shellcheck disable=SC2329
        log_warn()  { echo "WARN: $*"; }
        # shellcheck disable=SC2329
        log_error() { echo "ERROR: $*"; }
        # shellcheck disable=SC2329
        get-elevation-command() { echo ""; }
        # shellcheck disable=SC2329
        dnf()     { echo "PKG: dnf $*"; }
        # shellcheck disable=SC2329
        yum()     { echo "PKG: yum $*"; }
        # shellcheck disable=SC2329
        zypper()  { echo "PKG: zypper $*"; }
        # shellcheck disable=SC2329
        dpkg()    { echo "PKG: dpkg $*"; }
        # shellcheck disable=SC2329
        apt-get() { echo "PKG: apt-get $*"; }
        # shellcheck disable=SC1090,SC1091
        source "${REPO_ROOT}/shell/installers.sh"
        # Defined after sourcing: installers.sh defines the real ones.
        # shellcheck disable=SC2329
        _tenv_fetch_and_verify() {
            [[ "${verified}" == "fail" ]] && { echo "ERROR: verification failed"; return 1; }
            _TENV_VERIFIED_ASSET="$1/tenv-asset"
            : > "${_TENV_VERIFIED_ASSET}"
            _TENV_COSIGN_VERIFIED="${verified}"
        }
        # shellcheck disable=SC2329
        _tenv-install-tarball() { echo "TARBALL: $*"; }
        "${func}" v9.9.9 '{}'
    ) 2>&1
}

# 1-6. No cosign: rpm and deb fall back to the tarball, as root nothing.
for func in _tenv-install-rpm _tenv-install-deb; do
    out="$(run_install "${func}" false)"; rc=$?
    if [[ ${rc} -eq 0 && "${out}" != *"PKG:"* && "${out}" == *"TARBALL: v9.9.9 {}"* \
          && "${out}" == *"wb tools install cosign"* ]]; then
        ok "${func}: without cosign, installs the tarball instead and says how to get cosign"
    else
        fail "${func} fallback (rc=${rc}): ${out}"
    fi

    out="$(run_install "${func}" false TENV_INSTALL_REQUIRE_COSIGN=true)"; rc=$?
    if [[ ${rc} -ne 0 && "${out}" != *"PKG:"* && "${out}" != *"TARBALL:"* ]]; then
        ok "${func}: TENV_INSTALL_REQUIRE_COSIGN=true refuses, no package, no tarball"
    else
        fail "${func} require-cosign (rc=${rc}): ${out}"
    fi

    out="$(run_install "${func}" fail)"; rc=$?
    if [[ ${rc} -ne 0 && "${out}" != *"PKG:"* && "${out}" != *"TARBALL:"* ]]; then
        ok "${func}: a failed verification stops the install, no tarball fallback"
    else
        fail "${func} failed verification (rc=${rc}): ${out}"
    fi
done

# 7-8. Cosign verified: the package installs, as before.
out="$(run_install _tenv-install-rpm true)"; rc=$?
if [[ ${rc} -eq 0 && "${out}" == *"PKG: dnf install -y"* && "${out}" != *"TARBALL:"* ]]; then
    ok "dnf path installs when cosign verified the asset"
else
    fail "dnf install (rc=${rc}): ${out}"
fi
out="$(run_install _tenv-install-deb true)"; rc=$?
if [[ ${rc} -eq 0 && "${out}" == *"PKG: dpkg -i"* && "${out}" != *"TARBALL:"* ]]; then
    ok "apt (.deb) path installs when cosign verified the asset"
else
    fail "deb install (rc=${rc}): ${out}"
fi

# 9-11. The tarball path asks for this host's architecture only.
# run_tarball_arch <WORKBENCH_ARCH> — prints the asset pattern requested.
run_tarball_arch() {
    (
        # shellcheck disable=SC2030,SC2031  # per-run environment, deliberately subshell-local
        export WORKBENCH_ARCH="$1"
        # shellcheck disable=SC2329
        log_info()  { :; }
        # shellcheck disable=SC2329
        log_error() { echo "ERROR: $*"; }
        # shellcheck disable=SC1090,SC1091
        source "${REPO_ROOT}/shell/installers.sh"
        # shellcheck disable=SC2329
        _tenv_fetch_and_verify() { echo "PATTERN: $3"; return 1; }
        _tenv-install-tarball v9.9.9 '{}'
    ) 2>&1
}
out="$(run_tarball_arch x86_64)"
if [[ "${out}" == *'PATTERN: tenv_v9.9.9_Linux_x86_64\.tar\.gz'* ]]; then
    ok "tarball on x86_64 asks for tenv_<tag>_Linux_x86_64.tar.gz"
else
    fail "tarball x86_64 pattern: ${out}"
fi
out="$(run_tarball_arch aarch64)"
if [[ "${out}" == *'PATTERN: tenv_v9.9.9_Linux_arm64\.tar\.gz'* ]]; then
    ok "tarball on aarch64 asks for tenv_<tag>_Linux_arm64.tar.gz"
else
    fail "tarball aarch64 pattern: ${out}"
fi
out="$(run_tarball_arch riscv64)"; rc=$?
if [[ ${rc} -ne 0 && "${out}" == *"unsupported architecture"* && "${out}" != *"PATTERN:"* ]]; then
    ok "tarball on an unknown architecture refuses before any download"
else
    fail "tarball unknown arch (rc=${rc}): ${out}"
fi

# 12-15. _tenv_fetch_and_verify checks the asset's own checksum line.
ASSET="tenv_v9.9.9_Linux_x86_64.tar.gz"
SRV="${WORK}/srv"
mkdir -p "${SRV}"
printf 'tenv payload\n' > "${SRV}/${ASSET}"
printf 'some other file\n' > "${SRV}/tenv_v9.9.9_Linux_arm64.tar.gz"
sha_of() { sha256sum "$1" | awk '{ print $1 }'; }
GOOD_SHA="$(sha_of "${SRV}/${ASSET}")"
OTHER_SHA="$(sha_of "${SRV}/tenv_v9.9.9_Linux_arm64.tar.gz")"
WRONG_SHA="0000000000000000000000000000000000000000000000000000000000000000"
API_JSON="$(printf '{"assets":[{"browser_download_url": "https://example.invalid/%s"},{"browser_download_url": "https://example.invalid/tenv_v9.9.9_Linux_arm64.tar.gz"},{"browser_download_url": "https://example.invalid/tenv_9.9.9_checksums.txt"}]}' "${ASSET}")"

# run_verify <checksums-file-contents> — prints output, exits with rc.
run_verify() {
    printf '%s\n' "$1" > "${SRV}/tenv_9.9.9_checksums.txt"
    (
        # shellcheck disable=SC2329
        log_info()  { :; }
        # shellcheck disable=SC2329
        log_warn()  { :; }
        # shellcheck disable=SC2329
        log_error() { echo "ERROR: $*"; }
        # shellcheck disable=SC2329
        _download_file_robust() { cp "${SRV}/${1##*/}" "$2"; }
        # shellcheck disable=SC2329
        _wb_sha256() { sha256sum "$1" | awk '{ print $1 }'; }
        # shellcheck disable=SC1090,SC1091
        source "${REPO_ROOT}/shell/installers.sh"
        local tmp; tmp="$(mktemp -d "${WORK}/verify.XXXXXX")"
        _tenv_fetch_and_verify "${tmp}" v9.9.9 'tenv_v9\.9\.9_Linux_x86_64\.tar\.gz' "${API_JSON}" \
            && echo "VERIFIED: ${_TENV_VERIFIED_ASSET##*/}"
    ) 2>&1
}

out="$(run_verify "$(printf '%s  %s\n%s  %s' "${OTHER_SHA}" "tenv_v9.9.9_Linux_arm64.tar.gz" "${WRONG_SHA}" "${ASSET}")")"; rc=$?
if [[ ${rc} -ne 0 && "${out}" == *"SHA256 verification of ${ASSET} failed"* && "${out}" != *"VERIFIED:"* ]]; then
    ok "checksum: a matching other file does not pass a wrong hash for the asset"
else
    fail "checksum other-file (rc=${rc}): ${out}"
fi
out="$(run_verify "$(printf '%s  %s' "${OTHER_SHA}" "tenv_v9.9.9_Linux_arm64.tar.gz")")"; rc=$?
if [[ ${rc} -ne 0 && "${out}" != *"VERIFIED:"* ]]; then
    ok "checksum: no line for the asset fails"
else
    fail "checksum missing line (rc=${rc}): ${out}"
fi
out="$(run_verify "$(printf '%s  %s\n%s  %s' "${OTHER_SHA}" "tenv_v9.9.9_Linux_arm64.tar.gz" "${GOOD_SHA}" "${ASSET}")")"; rc=$?
if [[ ${rc} -eq 0 && "${out}" == *"VERIFIED: ${ASSET}"* ]]; then
    ok "checksum: the asset's right hash passes"
else
    fail "checksum right hash (rc=${rc}): ${out}"
fi
out="$(run_verify "$(printf '%s *%s' "$(printf '%s' "${GOOD_SHA}" | tr '[:lower:]' '[:upper:]')" "${ASSET}")")"; rc=$?
if [[ ${rc} -eq 0 && "${out}" == *"VERIFIED: ${ASSET}"* ]]; then
    ok "checksum: the '<hex> *<name>' form (upper-case hex) passes"
else
    fail "checksum *name form (rc=${rc}): ${out}"
fi

echo
echo "==============================="
echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
echo "==============================="
exit "${FAILED}"
