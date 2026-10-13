#!/usr/bin/env bash
# tests/check-version-lookups.sh — workbench-iac
# Functional checks for the Terraform/OpenTofu latest-version lookups
# (shell/terraform.sh) and for the fail-fast mktemp handling in the tenv
# installers (shell/installers.sh), with curl/mktemp stubbed. Plain bash,
# numbered OK:/FAIL: checks, matching workbench-core's tests/check-*.sh
# convention.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

# run_lookup <function> <curl-stub-body>
# Sources shell/terraform.sh with curl stubbed; echoes stdout+stderr, exits
# with the function's rc.
run_lookup() {
    local func="$1" curl_body="$2"
    (
        # shellcheck disable=SC2329  # stubs, invoked by the sourced file
        log_error() { echo "ERROR: $*"; }
        # shellcheck disable=SC2329
        _wb_declare_availability() { :; }
        # shellcheck disable=SC2329
        _wb_alias_availability() { :; }
        eval "curl() { ${curl_body}; }"
        # shellcheck disable=SC1090,SC1091
        source "${REPO_ROOT}/shell/terraform.sh"
        "${func}"
    ) 2>&1
}

# 1-3. get-latest-terraform-version
out="$(run_lookup get-latest-terraform-version 'echo "{\"current_version\":\"1.9.8\",\"name\":\"terraform\"}"')"; rc=$?
if [[ ${rc} -eq 0 && "${out}" == "1.9.8" ]]; then ok "terraform: version parsed from the checkpoint response"; else fail "terraform success (rc=${rc}): ${out}"; fi
out="$(run_lookup get-latest-terraform-version 'return 22')"; rc=$?
if [[ ${rc} -ne 0 && "${out}" == *"Could not query HashiCorp"* ]]; then ok "terraform: curl failure returns non-zero with a clear error"; else fail "terraform curl failure (rc=${rc}): ${out}"; fi
out="$(run_lookup get-latest-terraform-version 'echo "<html>oops</html>"')"; rc=$?
if [[ ${rc} -ne 0 && "${out}" == *"Could not determine the latest Terraform version"* ]]; then ok "terraform: unparseable response returns non-zero with a clear error"; else fail "terraform bad response (rc=${rc}): ${out}"; fi

# 4-6. get-latest-opentofu-version
out="$(run_lookup get-latest-opentofu-version 'echo "{\"tag_name\": \"v1.8.3\"}"')"; rc=$?
if [[ ${rc} -eq 0 && "${out}" == "1.8.3" ]]; then ok "opentofu: version parsed from the release response"; else fail "opentofu success (rc=${rc}): ${out}"; fi
out="$(run_lookup get-latest-opentofu-version 'return 22')"; rc=$?
if [[ ${rc} -ne 0 && "${out}" == *"Could not query GitHub"* ]]; then ok "opentofu: curl failure returns non-zero with a clear error"; else fail "opentofu curl failure (rc=${rc}): ${out}"; fi
out="$(run_lookup get-latest-opentofu-version 'echo "{\"message\": \"rate limited\"}"')"; rc=$?
if [[ ${rc} -ne 0 && "${out}" == *"Could not determine the latest OpenTofu version"* ]]; then ok "opentofu: unparseable response returns non-zero with a clear error"; else fail "opentofu bad response (rc=${rc}): ${out}"; fi

# 7-10. mktemp failure is fatal before anything is downloaded
# run_mktemp_fail <function>
run_mktemp_fail() {
    local func="$1"
    (
        export WORKBENCH_ARCH=x86_64
        # shellcheck disable=SC2329
        log_info()  { echo "INFO: $*"; }
        # shellcheck disable=SC2329
        log_error() { echo "ERROR: $*"; }
        # shellcheck disable=SC2329
        mktemp()    { return 1; }
        # shellcheck disable=SC1090,SC1091
        source "${REPO_ROOT}/shell/installers.sh"
        # Defined after sourcing: installers.sh defines the real one.
        # shellcheck disable=SC2329
        _tenv_fetch_and_verify() { echo "FETCHED"; }
        "${func}" v9.9.9 '{}'
    ) 2>&1
}
for func in _tenv-install-rpm _tenv-install-deb _tenv-install-arch _tenv-install-tarball; do
    out="$(run_mktemp_fail "${func}")"; rc=$?
    if [[ ${rc} -ne 0 && "${out}" == *"could not create a temporary directory"* && "${out}" != *"FETCHED"* ]]; then
        ok "${func}: mktemp failure aborts before any download"
    else
        fail "${func} mktemp failure (rc=${rc}): ${out}"
    fi
done

echo
echo "==============================="
echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
echo "==============================="
exit "${FAILED}"
