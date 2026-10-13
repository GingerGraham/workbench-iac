#!/usr/bin/env bash
# tests/check-ansible-install.sh — workbench-iac
# Functional checks for _ansible-install-python's PyPI version lookup, with
# curl/pip3 stubbed. Plain bash, numbered OK:/FAIL: checks, matching
# workbench-core's tests/check-*.sh convention.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

# run_lookup <curl-stub-body>
# Runs _ansible-install-python in a subshell; echoes output, exits with its rc.
run_lookup() {
    local curl_body="$1"
    (
        # shellcheck disable=SC2329  # stubs, invoked by the sourced installers
        log_info()  { echo "INFO: $*"; }
        # shellcheck disable=SC2329
        log_error() { echo "ERROR: $*"; }
        # shellcheck disable=SC2329
        pip3()      { echo "PIP3: $*"; }
        eval "curl() { ${curl_body}; }"
        # shellcheck disable=SC1090,SC1091
        source "${REPO_ROOT}/shell/installers.sh"
        _ansible-install-python
    ) 2>&1
}

out="$(run_lookup 'echo "{\"info\":{\"version\":\"13.0.0\",\"name\":\"ansible\"}}"')"; rc=$?
if [[ ${rc} -eq 0 && "${out}" == *"Installing Ansible 13.0.0"* ]]; then
    ok "version parsed from PyPI JSON and pip3 invoked"
else
    fail "success path (rc=${rc}): ${out}"
fi

out="$(run_lookup 'return 22')"; rc=$?
if [[ ${rc} -ne 0 && "${out}" == *"Could not query PyPI"* && "${out}" != *"PIP3"* ]]; then
    ok "curl failure (HTTP error) aborts before pip3 runs"
else
    fail "curl failure (rc=${rc}): ${out}"
fi

out="$(run_lookup 'echo "<html>not json</html>"')"; rc=$?
if [[ ${rc} -ne 0 && "${out}" == *"Could not determine latest Ansible version"* && "${out}" != *"PIP3"* ]]; then
    ok "unparseable response aborts before pip3 runs"
else
    fail "bad response (rc=${rc}): ${out}"
fi

echo
echo "==============================="
echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
echo "==============================="
exit "${FAILED}"
