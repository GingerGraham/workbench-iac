#!/usr/bin/env bash
# tests/check-tflint-install.sh — workbench-iac
# Functional checks for _tflint-install-linux's install and symlink-swap
# steps, with the network and core helpers stubbed. Plain bash, numbered
# OK:/FAIL: checks, matching workbench-core's tests/check-*.sh convention.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

if ! command -v unzip >/dev/null 2>&1 || ! command -v zip >/dev/null 2>&1; then
    echo "SKIP: zip/unzip not available"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# Fake release zip: a "tflint" that reports 9.9.9.
FAKE_SRC="${WORK}/fake-src"
mkdir -p "${FAKE_SRC}"
printf '#!/bin/sh\necho "TFLint version 9.9.9"\n' > "${FAKE_SRC}/tflint"
chmod +x "${FAKE_SRC}/tflint"
( cd "${FAKE_SRC}" && zip -q "${WORK}/tflint_linux_amd64.zip" tflint )

# run_install <home> [extra stub definitions]
# Runs _tflint-install-linux in a subshell with HOME=<home>; prints its output
# and exits with its return code.
run_install() {
    local home="$1" extra="${2:-}"
    (
        export HOME="${home}"
        export PATH="${home}/.local/bin:${PATH}"
        export WORKBENCH_ARCH=x86_64
        # shellcheck disable=SC2329  # stubs, invoked by the sourced installers
        log_info()  { echo "INFO: $*"; }
        # shellcheck disable=SC2329
        log_error() { echo "ERROR: $*"; }
        # shellcheck disable=SC2329
        curl() { echo '"tag_name": "v9.9.9",'; }
        # shellcheck disable=SC2329
        _wb_gh_asset_digest() { echo "deadbeef"; }
        # shellcheck disable=SC2329
        _wb_fetch_verified() {
            # Record the URL so the asset-name check below can read it.
            echo "${1}" > "${WORK}/fetched-url"
            cp "${WORK}/tflint_linux_amd64.zip" "${2}"
        }
        # shellcheck disable=SC1090,SC1091
        source "${REPO_ROOT}/shell/installers.sh"
        eval "${extra}"
        _tflint-install-linux
    ) 2>&1
}

new_home() { local h; h="$(mktemp -d "${WORK}/home.XXXXXX")"; mkdir -p "${h}/.local/bin"; echo "${h}"; }

# 1. Fresh install
H="$(new_home)"
out="$(run_install "${H}")"; rc=$?
if [[ ${rc} -eq 0 && -L "${H}/.local/bin/tflint" && -x "${H}/.local/bin/tf-lint/tflint-9.9.9/tflint" ]]; then
    ok "fresh install succeeds and links ~/.local/bin/tflint"
else
    fail "fresh install (rc=${rc}): ${out}"
fi

# 2. Asset name and URL
if [[ "$(cat "${WORK}/fetched-url" 2>/dev/null)" == "https://github.com/terraform-linters/tflint/releases/download/v9.9.9/tflint_linux_amd64.zip" ]]; then
    ok "downloads tflint_linux_<arch>.zip from the tagged release"
else
    fail "unexpected asset URL: $(cat "${WORK}/fetched-url" 2>/dev/null)"
fi

# 3. Existing regular file is moved aside, not lost
H="$(new_home)"
printf '#!/bin/sh\necho "TFLint version 0.0.1"\n' > "${H}/.local/bin/tflint"; chmod +x "${H}/.local/bin/tflint"
out="$(run_install "${H}")"; rc=$?
if [[ ${rc} -eq 0 && -L "${H}/.local/bin/tflint" && -f "${H}/.local/bin/tflint.old" ]]; then
    ok "existing regular tflint is kept as tflint.old"
else
    fail "regular-file swap (rc=${rc}): ${out}"
fi

# 4. mkdir of the install dir fails -> nonzero, existing tflint untouched
H="$(new_home)"
printf '#!/bin/sh\necho "TFLint version 0.0.1"\n' > "${H}/.local/bin/tflint"; chmod +x "${H}/.local/bin/tflint"
: > "${H}/.local/bin/tf-lint"   # a file where the install dir must go
out="$(run_install "${H}")"; rc=$?
if [[ ${rc} -ne 0 && -f "${H}/.local/bin/tflint" && ! -L "${H}/.local/bin/tflint" && ! -e "${H}/.local/bin/tflint.old" ]]; then
    ok "failed mkdir leaves the existing tflint untouched"
else
    fail "mkdir failure (rc=${rc}): ${out}"
fi

# 5. install fails -> nonzero, existing tflint untouched
H="$(new_home)"
printf '#!/bin/sh\necho "TFLint version 0.0.1"\n' > "${H}/.local/bin/tflint"; chmod +x "${H}/.local/bin/tflint"
out="$(run_install "${H}" 'install() { return 1; }')"; rc=$?
if [[ ${rc} -ne 0 && -f "${H}/.local/bin/tflint" && ! -L "${H}/.local/bin/tflint" && ! -e "${H}/.local/bin/tflint.old" && "${out}" == *"failed to install binary"* ]]; then
    ok "failed install leaves the existing tflint untouched and reports it"
else
    fail "install failure (rc=${rc}): ${out}"
fi

# 6. Temp-link creation fails -> nonzero, existing tflint untouched, no "installed"
H="$(new_home)"
printf '#!/bin/sh\necho "TFLint version 0.0.1"\n' > "${H}/.local/bin/tflint"; chmod +x "${H}/.local/bin/tflint"
out="$(run_install "${H}" 'ln() { return 1; }')"; rc=$?
if [[ ${rc} -ne 0 && -f "${H}/.local/bin/tflint" && ! -L "${H}/.local/bin/tflint" && "${out}" != *"installed"* ]]; then
    ok "failed symlink creation leaves the existing tflint untouched"
else
    fail "ln failure (rc=${rc}): ${out}"
fi

# 7. Final rename fails after the old one was moved aside -> old one restored
H="$(new_home)"
printf '#!/bin/sh\necho "TFLint version 0.0.1"\n' > "${H}/.local/bin/tflint"; chmod +x "${H}/.local/bin/tflint"
# shellcheck disable=SC2016  # the stub is eval'd later, expand then
out="$(run_install "${H}" 'mv() { if [[ "${1:-}" == "-f" ]]; then return 1; fi; command mv "$@"; }')"; rc=$?
if [[ ${rc} -ne 0 && -f "${H}/.local/bin/tflint" && ! -L "${H}/.local/bin/tflint" && ! -e "${H}/.local/bin/tflint.old" ]]; then
    ok "failed final rename restores the previous tflint"
else
    fail "restore (rc=${rc}): ${out}"
fi
if ls "${H}/.local/bin"/.tflint.new.* >/dev/null 2>&1; then
    fail "temporary link left behind after failure"
else
    ok "no temporary link left behind after failure"
fi

# 9-10. An existing tflint that is a symlink elsewhere on PATH is recorded and
# removed on success, and put back (same target) when the final rename fails.
make_other_symlink() {
    local h="$1"
    mkdir -p "${h}/other"
    printf '#!/bin/sh\necho "TFLint version 0.0.1"\n' > "${h}/other/real-tflint"; chmod +x "${h}/other/real-tflint"
    ln -s "${h}/other/real-tflint" "${h}/other/tflint"
}

H="$(new_home)"
make_other_symlink "${H}"
# shellcheck disable=SC2016  # the stub is eval'd later, expand then
out="$(run_install "${H}" 'PATH="${HOME}/other:${PATH}"')"; rc=$?
if [[ ${rc} -eq 0 && ! -e "${H}/other/tflint" && ! -L "${H}/other/tflint" && -L "${H}/.local/bin/tflint" ]]; then
    ok "existing symlink elsewhere on PATH is removed and our link installed"
else
    fail "symlink displacement (rc=${rc}): ${out}"
fi

H="$(new_home)"
make_other_symlink "${H}"
# shellcheck disable=SC2016  # the stub is eval'd later, expand then
out="$(run_install "${H}" 'PATH="${HOME}/other:${PATH}"; mv() { if [[ "${1:-}" == "-f" ]]; then return 1; fi; command mv "$@"; }')"; rc=$?
if [[ ${rc} -ne 0 && -L "${H}/other/tflint" && "$(readlink "${H}/other/tflint")" == "${H}/other/real-tflint" && ! -e "${H}/.local/bin/tflint" ]]; then
    ok "failed final rename restores the displaced symlink with its original target"
else
    fail "symlink restore (rc=${rc}): ${out}"
fi

echo
echo "==============================="
echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
echo "==============================="
exit "${FAILED}"
