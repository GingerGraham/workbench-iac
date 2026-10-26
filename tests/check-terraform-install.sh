#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2317  # literal $releasever/$basearch; shellcheck <0.10 reports stubs as unreachable (0.10+: SC2329, annotated at each site)
# tests/check-terraform-install.sh — workbench-iac
# Functional checks for install-terraform (workbench-core D103): HashiCorp's
# dnf repository, apt repository and signature-verified release zip. No
# network: downloads go through a curl shim serving local fixtures, package
# managers are stubs that print "PKG: <argv>", and /etc is redirected with
# _WB_TEST_SYSROOT (the same hook workbench-core's vendor-key helpers use).
#
# The Core API helpers (_wb_dnf_vendor_repo, _wb_apt_keyring_pinned, ...)
# are recording stubs here, so this runs standalone in module CI. When a
# workbench-core checkout is found (WORKBENCH_CORE_DIR, or ../workbench-core),
# the rpm, deb and zip paths also run once against the real helpers, with
# throwaway gpg keys standing in for HashiCorp's. Plain bash, numbered
# OK:/FAIL: checks, matching workbench-core's tests/check-*.sh convention.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FAILED=0
check_no=0
ok()   { check_no=$((check_no + 1)); echo "OK:   [$check_no] $*"; }
fail() { check_no=$((check_no + 1)); echo "FAIL: [$check_no] $*"; FAILED=$((FAILED + 1)); }

WORK="$(mktemp -d)"
cleanup() {
    local d
    for d in "${WORK}"/gh-*; do
        [[ -d "${d}" ]] && gpgconf --homedir "${d}" --kill all >/dev/null 2>&1
    done
    rm -rf "${WORK}"
}
trap cleanup EXIT

PKG_FPR="D55C0D1AC78A8D8126CB631CFC9CA96ACA026560"      # gitleaks:allow
RELEASE_FPR="C874011F0AB405110D02105534365D9472D7468F"  # gitleaks:allow

CORE_LIB=""
for _c in "${WORKBENCH_CORE_DIR:-}" "${REPO_ROOT}/../workbench-core"; do
    if [[ -n "${_c}" && -f "${_c}/lib/core/installers-common.sh" ]]; then
        CORE_LIB="$(cd "${_c}/lib/core" && pwd)"
        break
    fi
done

# ── curl shim: serves ${SRV}/<last URL segment>, logs every URL ───────────────
SRV="${WORK}/srv"
FETCH_LOG="${WORK}/fetch.log"
mkdir -p "${WORK}/bin" "${SRV}"
cat > "${WORK}/bin/curl" <<SHIM
#!/usr/bin/env bash
out=""; url=""
while [[ \$# -gt 0 ]]; do
    case "\$1" in
        --output|-o) out="\$2"; shift 2 ;;
        -*) shift ;;
        *) url="\$1"; shift ;;
    esac
done
echo "\${url}" >> "${FETCH_LOG}"
[[ -f "${SRV}/\${url##*/}" ]] || exit 22
cp "${SRV}/\${url##*/}" "\${out}"
SHIM
chmod +x "${WORK}/bin/curl"

# ── Stand-ins for the Core API download helpers when core isn't available ────
# Same contracts as lib/core/installers-common.sh; fail closed the same way.
if [[ -z "${CORE_LIB}" ]]; then
    # shellcheck disable=SC2329  # invoked by the sourced installers
    _download_file_robust() { "${WORK}/bin/curl" --output "$2" "$1"; }
    # shellcheck disable=SC2329
    _wb_sha256() {
        if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{ print $1 }'
        else shasum -a 256 "$1" | awk '{ print $1 }'; fi
    }
    # shellcheck disable=SC2329
    _wb_fetch_verified() {
        local t; t="$(mktemp -d)" || return 1
        _download_file_robust "$1" "${t}/payload" || { rm -rf "${t}"; return 1; }
        if [[ "$(_wb_sha256 "${t}/payload")" != "$3" ]]; then
            echo "ERROR: SHA-256 mismatch for ${1##*/}"; rm -rf "${t}"; return 1
        fi
        mv -f "${t}/payload" "$2"; rm -rf "${t}"
    }
    # shellcheck disable=SC2329
    _wb_key_extract_pinned() {
        local in="$1" out="$2" want="$4" gh rc=1
        gh="$(mktemp -d)" || return 1
        gpg --homedir "${gh}" --batch --quiet --import "${in}" >/dev/null 2>&1
        if gpg --homedir "${gh}" --batch --with-colons --list-keys 2>/dev/null \
                | awk -F: 'p == "pub" && $1 == "fpr" { print $10 } { p = $1 }' | grep -qx "${want}"; then
            gpg --homedir "${gh}" --batch --export "${want}" > "${out}" && rc=0
        fi
        gpgconf --homedir "${gh}" --kill all >/dev/null 2>&1
        rm -rf "${gh}"
        return "${rc}"
    }
fi

# tf_run <stub|core> <command> [args...]
# Runs <command> from shell/installers.sh in a subshell, from the empty
# directory ${SCRATCH}, with HOME=${T_HOME} and _WB_TEST_SYSROOT=${T_ROOT}.
# "stub" replaces _wb_dnf_vendor_repo/_wb_apt_keyring_pinned with recorders
# ("CALL: <argv>") that succeed unless KEY_OK=false; "core" keeps core's.
# TEST_FPR, when set, stands in for both HashiCorp fingerprints.
tf_run() {
    local helpers="$1"; shift
    (
        cd "${SCRATCH}" || exit 99
        # Stubs write to stderr, as core's log_* and the real tools' chatter
        # would: a Core API helper's stdout can be its return value.
        export HOME="${T_HOME}" _WB_TEST_SYSROOT="${T_ROOT}" PATH="${WORK}/bin:${PATH}"
        # shellcheck disable=SC2329  # stubs, invoked by the sourced installers
        log_info()  { echo "INFO: $*" >&2; }
        # shellcheck disable=SC2329
        log_warn()  { echo "WARN: $*" >&2; }
        # shellcheck disable=SC2329
        log_error() { echo "ERROR: $*" >&2; }
        # shellcheck disable=SC2329
        get-elevation-command() { :; }
        # shellcheck disable=SC2329
        dnf()     { echo "PKG: dnf $*" >&2; }
        # shellcheck disable=SC2329
        yum()     { echo "PKG: yum $*" >&2; }
        # shellcheck disable=SC2329
        apt-get() { echo "PKG: apt-get $*" >&2; }
        # shellcheck disable=SC2329
        brew()    { echo "PKG: brew $*" >&2; [[ "$1" != "list" ]]; }
        # shellcheck disable=SC2329
        rpm()     { [[ "$1" == "-q" ]] && return 1; echo "PKG: rpm $*" >&2; }
        # shellcheck disable=SC2329
        dpkg()    { [[ "$1" == "--print-architecture" ]] && { echo amd64; return 0; }; echo "PKG: dpkg $*" >&2; }
        if [[ -n "${CORE_LIB}" ]]; then
            # shellcheck disable=SC1090,SC1091
            source "${CORE_LIB}/installers-common.sh"
        fi
        # shellcheck disable=SC1090,SC1091
        source "${REPO_ROOT}/shell/installers.sh"
        if [[ -n "${TEST_FPR:-}" ]]; then
            _HASHICORP_PKG_KEY_FPR="${TEST_FPR}"
            _HASHICORP_RELEASE_KEY_FPR="${TEST_FPR}"
        fi
        if [[ "${helpers}" == "stub" ]]; then
            # shellcheck disable=SC2329
            _wb_dnf_vendor_repo()    { echo "CALL: _wb_dnf_vendor_repo $*"; [[ "${KEY_OK:-true}" == "true" ]]; }
            # shellcheck disable=SC2329
            _wb_apt_keyring_pinned() { echo "CALL: _wb_apt_keyring_pinned $*"; [[ "${KEY_OK:-true}" == "true" ]]; }
        fi
        "$@"
    ) 2>&1
}

# new_scenario — fresh HOME, sysroot and scratch directory.
new_scenario() {
    T_HOME="$(mktemp -d "${WORK}/home.XXXXXX")"
    T_ROOT="$(mktemp -d "${WORK}/root.XXXXXX")"
    SCRATCH="$(mktemp -d "${WORK}/cwd.XXXXXX")"
    mkdir -p "${T_ROOT}/etc"
    : > "${FETCH_LOG}"
}
os_release() { printf '%s\n' "$@" > "${T_ROOT}/etc/os-release"; }

# Every scratch directory used as the working directory must stay empty (H7:
# tfenv's update path wrote into the current directory).
SCRATCH_DIRS=""
remember_scratch() { SCRATCH_DIRS="${SCRATCH_DIRS} ${SCRATCH}"; }

# 1. Pinned fingerprints
if grep -q "^_HASHICORP_PKG_KEY_FPR=\"${PKG_FPR}\"" "${REPO_ROOT}/shell/installers.sh" \
   && grep -q "^_HASHICORP_RELEASE_KEY_FPR=\"${RELEASE_FPR}\"" "${REPO_ROOT}/shell/installers.sh"; then
    ok "HashiCorp package and release key fingerprints are pinned"
else
    fail "pinned HashiCorp fingerprints differ from ${PKG_FPR} / ${RELEASE_FPR}"
fi

# 2. install-trivy and tfenv are gone from install-terraform
# Log messages are left out: the tfenv warning tells the user which tfenv
# commands they can run.
if grep -vE '^[[:space:]]*#|log_(info|warn|error) ' "${REPO_ROOT}/shell/installers.sh" | grep -qE 'install-trivy|tfenv (install|use)|tfutils/tfenv'; then
    fail "shell/installers.sh still runs tfenv or install-trivy"
else
    ok "install-terraform no longer runs tfenv or install-trivy"
fi

# ── rpm (recording helpers) ──────────────────────────────────────────────────
# 3. Fedora
new_scenario; remember_scratch; os_release 'NAME="Fedora Linux"' 'ID=fedora'
out="$(tf_run stub _tf-install-rpm)"; rc=$?
if [[ ${rc} -eq 0 && "${out}" == *"CALL: _wb_dnf_vendor_repo --id workbench-hashicorp "* \
      && "${out}" == *"--baseurl https://rpm.releases.hashicorp.com/fedora/\$releasever/\$basearch/stable "* \
      && "${out}" == *"--key-url https://rpm.releases.hashicorp.com/gpg --fingerprint ${PKG_FPR} --include terraform"* \
      && "${out}" == *"PKG: dnf install -y terraform"* ]]; then
    ok "rpm (Fedora): workbench-hashicorp repo, fedora baseurl, pinned key, terraform only; dnf install"
else
    fail "rpm Fedora (rc=${rc}): ${out}"
fi

# 4. RHEL family
new_scenario; remember_scratch; os_release 'ID="rocky"' 'ID_LIKE="rhel centos fedora"'
out="$(tf_run stub _tf-install-rpm)"; rc=$?
if [[ ${rc} -eq 0 && "${out}" == *"--baseurl https://rpm.releases.hashicorp.com/RHEL/\$releasever/\$basearch/stable "* ]]; then
    ok "rpm (Rocky): RHEL baseurl"
else
    fail "rpm RHEL (rc=${rc}): ${out}"
fi

# 5. HashiCorp's own hashicorp.repo is used and left alone
new_scenario; remember_scratch; os_release 'ID=fedora'
mkdir -p "${T_ROOT}/etc/yum.repos.d"
printf '[hashicorp]\nname=Hashicorp Stable - $basearch\nbaseurl=https://rpm.releases.hashicorp.com/fedora/$releasever/$basearch/stable\nenabled=1\ngpgcheck=1\ngpgkey=https://rpm.releases.hashicorp.com/gpg\n' \
    > "${T_ROOT}/etc/yum.repos.d/hashicorp.repo"
cp "${T_ROOT}/etc/yum.repos.d/hashicorp.repo" "${WORK}/hashicorp.repo.orig"
out="$(tf_run stub _tf-install-rpm)"; rc=$?
if [[ ${rc} -eq 0 && "${out}" != *"CALL: _wb_dnf_vendor_repo"* && "${out}" == *"PKG: dnf install -y terraform"* \
      && ! -e "${T_ROOT}/etc/yum.repos.d/workbench-hashicorp.repo" ]] \
   && cmp -s "${WORK}/hashicorp.repo.orig" "${T_ROOT}/etc/yum.repos.d/hashicorp.repo"; then
    ok "rpm: an existing hashicorp.repo is used, left byte-identical, and no second repo is written"
else
    fail "rpm existing repo (rc=${rc}): ${out}"
fi

# 6. Key refusal
new_scenario; remember_scratch; os_release 'ID=fedora'
out="$(KEY_OK=false tf_run stub _tf-install-rpm)"; rc=$?
if [[ ${rc} -ne 0 && "${out}" != *"PKG: dnf"* && "${out}" == *"pinned key"* ]]; then
    ok "rpm: a served key without the pinned fingerprint refuses; nothing installed"
else
    fail "rpm key refusal (rc=${rc}): ${out}"
fi

# ── deb (recording helpers) ──────────────────────────────────────────────────
LIST_LINE="deb [arch=amd64 signed-by=/usr/share/keyrings/workbench-hashicorp.gpg] https://apt.releases.hashicorp.com jammy main"
# 7. Ubuntu derivative: UBUNTU_CODENAME wins over VERSION_CODENAME
new_scenario; remember_scratch; os_release 'ID=linuxmint' 'VERSION_CODENAME=virginia' 'UBUNTU_CODENAME=jammy'
out="$(tf_run stub _tf-install-deb)"; rc=$?
if [[ ${rc} -eq 0 \
      && "${out}" == *"CALL: _wb_apt_keyring_pinned https://apt.releases.hashicorp.com/gpg /usr/share/keyrings/workbench-hashicorp.gpg ${PKG_FPR}"* \
      && "$(cat "${T_ROOT}/etc/apt/sources.list.d/workbench-hashicorp.list" 2>/dev/null)" == "${LIST_LINE}" \
      && "${out}" == *"PKG: apt-get update"* && "${out}" == *"PKG: apt-get install -y terraform"* ]]; then
    ok "deb: keyring pinned to the package key, list has signed-by and UBUNTU_CODENAME; apt-get install"
else
    fail "deb (rc=${rc}): ${out} / list: $(cat "${T_ROOT}/etc/apt/sources.list.d/workbench-hashicorp.list" 2>/dev/null)"
fi

# 8. Debian: VERSION_CODENAME
new_scenario; remember_scratch; os_release 'ID=debian' 'VERSION_CODENAME=bookworm'
out="$(tf_run stub _tf-install-deb)"; rc=$?
if [[ ${rc} -eq 0 && "$(cat "${T_ROOT}/etc/apt/sources.list.d/workbench-hashicorp.list" 2>/dev/null)" == *" bookworm main" ]]; then
    ok "deb (Debian): codename from VERSION_CODENAME"
else
    fail "deb Debian (rc=${rc}): ${out}"
fi

# 9. HashiCorp's own source list is used and left alone
new_scenario; remember_scratch; os_release 'ID=ubuntu' 'VERSION_CODENAME=noble' 'UBUNTU_CODENAME=noble'
mkdir -p "${T_ROOT}/etc/apt/sources.list.d"
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com noble main" \
    > "${T_ROOT}/etc/apt/sources.list.d/hashicorp.list"
cp "${T_ROOT}/etc/apt/sources.list.d/hashicorp.list" "${WORK}/hashicorp.list.orig"
out="$(tf_run stub _tf-install-deb)"; rc=$?
if [[ ${rc} -eq 0 && "${out}" != *"CALL: _wb_apt_keyring_pinned"* && "${out}" == *"PKG: apt-get install -y terraform"* \
      && ! -e "${T_ROOT}/etc/apt/sources.list.d/workbench-hashicorp.list" ]] \
   && cmp -s "${WORK}/hashicorp.list.orig" "${T_ROOT}/etc/apt/sources.list.d/hashicorp.list"; then
    ok "deb: an existing HashiCorp source list is used, left byte-identical, and no second list is written"
else
    fail "deb existing list (rc=${rc}): ${out}"
fi

# 10. Key refusal
new_scenario; remember_scratch; os_release 'ID=ubuntu' 'UBUNTU_CODENAME=noble'
out="$(KEY_OK=false tf_run stub _tf-install-deb)"; rc=$?
if [[ ${rc} -ne 0 && "${out}" != *"PKG: apt-get"* && ! -e "${T_ROOT}/etc/apt/sources.list.d/workbench-hashicorp.list" ]]; then
    ok "deb: a served key without the pinned fingerprint refuses; no list written, nothing installed"
else
    fail "deb key refusal (rc=${rc}): ${out}"
fi

# ── macOS and dispatch ───────────────────────────────────────────────────────
# 11. Homebrew: HashiCorp's tap, not homebrew-core
new_scenario; remember_scratch
out="$(tf_run stub _tf-install-mac)"; rc=$?
if [[ ${rc} -eq 0 && "${out}" == *"PKG: brew tap hashicorp/tap"* && "${out}" == *"PKG: brew install hashicorp/tap/terraform"* ]]; then
    ok "macOS: brew tap hashicorp/tap and install hashicorp/tap/terraform"
else
    fail "macOS brew (rc=${rc}): ${out}"
fi

# 12-13. Dispatch, and the tfenv warning (~/.tfenv never touched)
dispatch_probe='_tf-install-rpm() { echo "ROUTE: rpm"; }; _tf-install-deb() { echo "ROUTE: deb"; };
    _tf-install-zip() { echo "ROUTE: zip $*"; }; _tf-install-mac() { echo "ROUTE: mac"; };
    _iac_latest_terraform_version() { echo 9.9.9; }; install-tflint() { echo "TFLINT"; }'
routes=""
for d in rhel debian suse arch unknown; do
    new_scenario; remember_scratch
    out="$(WORKBENCH_OS=Linux WORKBENCH_DISTRO="${d}" tf_run stub eval "${dispatch_probe}; install-terraform")"
    routes="${routes} ${d}=$(printf '%s\n' "${out}" | sed -n 's/^ROUTE: //p' | tr ' ' '-')"
done
if [[ "${routes}" == " rhel=rpm debian=deb suse=zip-9.9.9 arch=zip-9.9.9 unknown=zip-9.9.9" ]]; then
    ok "install-terraform: rhel→repo, debian→repo, suse/arch/unknown→zip of the latest version"
else
    fail "dispatch: ${routes}"
fi
new_scenario; remember_scratch
mkdir -p "${T_HOME}/.tfenv/bin"; printf '#!/bin/sh\n' > "${T_HOME}/.tfenv/bin/tfenv"
cp "${T_HOME}/.tfenv/bin/tfenv" "${WORK}/tfenv.orig"
out="$(WORKBENCH_OS=Linux WORKBENCH_DISTRO=rhel tf_run stub eval "${dispatch_probe}; install-terraform")"; rc=$?
if [[ ${rc} -eq 0 && "${out}" == *"tfenv is installed"* && "${out}" == *"tfenv install latest"* \
      && "${out}" == *"ROUTE: rpm"* && "${out}" == *"TFLINT"* ]] \
   && cmp -s "${WORK}/tfenv.orig" "${T_HOME}/.tfenv/bin/tfenv"; then
    ok "existing ~/.tfenv: warns, points at tfenv, carries on, leaves ~/.tfenv alone"
else
    fail "tfenv warning (rc=${rc}): ${out}"
fi

# An installed tenv: warn and point at tenv, then carry on.
new_scenario; remember_scratch
mkdir -p "${T_HOME}/.local/bin"; printf '#!/bin/sh\n' > "${T_HOME}/.local/bin/tenv"; chmod +x "${T_HOME}/.local/bin/tenv"
out="$(WORKBENCH_OS=Linux WORKBENCH_DISTRO=rhel tf_run stub eval "${dispatch_probe}; install-terraform")"; rc=$?
if [[ ${rc} -eq 0 && "${out}" == *"tenv is installed"* && "${out}" == *"tenv tf install latest"* && "${out}" == *"ROUTE: rpm"* ]]; then
    ok "installed tenv: warns, points at tenv, carries on"
else
    fail "tenv warning (rc=${rc}): ${out}"
fi

# The zip route never overwrites tenv's terraform proxy in ~/.local/bin.
printf '#!/bin/sh\necho tenv-proxy\n' > "${T_HOME}/.local/bin/terraform"; chmod +x "${T_HOME}/.local/bin/terraform"
cp "${T_HOME}/.local/bin/terraform" "${WORK}/proxy.orig"
out="$(WORKBENCH_OS=Linux WORKBENCH_ARCH=x86_64 tf_run stub _tf-install-zip 1.9.0)"; rc=$?
if [[ ${rc} -ne 0 && "${out}" == *"tenv's proxy"* ]] && cmp -s "${WORK}/proxy.orig" "${T_HOME}/.local/bin/terraform"; then
    ok "zip route: refuses to overwrite tenv's ~/.local/bin/terraform proxy"
else
    fail "zip route with tenv proxy (rc=${rc}): ${out}"
fi

# ── zip (signature + checksum) ───────────────────────────────────────────────
HAVE_ZIP_TOOLS=true
for t in gpg gpgv gpgconf zip unzip; do
    command -v "${t}" >/dev/null 2>&1 || HAVE_ZIP_TOOLS=false
done
FPR_GOOD=""; FPR_OTHER=""
if [[ "${HAVE_ZIP_TOOLS}" == "true" ]]; then
    fpr_of() {
        gpg --homedir "${WORK}/gh-$1" --batch --with-colons --list-keys 2>/dev/null \
            | awk -F: 'p == "pub" && $1 == "fpr" { print $10; exit } { p = $1 }'
    }
    for k in good other; do
        mkdir -p "${WORK}/gh-${k}"; chmod 700 "${WORK}/gh-${k}"
        gpg --homedir "${WORK}/gh-${k}" --batch --passphrase '' \
            --quick-gen-key "key-${k} <${k}@example.invalid>" default default never >"${WORK}/gen-${k}.log" 2>&1
    done
    FPR_GOOD="$(fpr_of good)"; FPR_OTHER="$(fpr_of other)"
fi

if [[ -z "${FPR_GOOD}" || -z "${FPR_OTHER}" ]]; then
    echo "SKIP: gpg/gpgv/zip/unzip or gpg key generation unavailable — zip and real-helper checks not run"
else
    V="9.9.9"
    ZIPNAME="terraform_${V}_linux_amd64.zip"
    SUMS="terraform_${V}_SHA256SUMS"
    mkdir -p "${WORK}/zipsrc"
    printf '#!/bin/sh\necho "Terraform v%s"\n' "${V}" > "${WORK}/zipsrc/terraform"
    chmod +x "${WORK}/zipsrc/terraform"
    ( cd "${WORK}/zipsrc" && zip -q "${WORK}/${ZIPNAME}" terraform )
    sha_file() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{ print $1 }'; else shasum -a 256 "$1" | awk '{ print $1 }'; fi; }

    # serve_zip <signer: good|other> <served release key: good|other> <sums sha: right|wrong>
    serve_zip() {
        rm -f "${SRV}"/*
        cp "${WORK}/${ZIPNAME}" "${SRV}/${ZIPNAME}"
        local sha; sha="$(sha_file "${SRV}/${ZIPNAME}")"
        [[ "$3" == "wrong" ]] && sha="0000000000000000000000000000000000000000000000000000000000000000"
        printf '%s  %s\n%s  %s\n' "$(sha_file "${SRV}/${ZIPNAME}" | tr 0-9a-f a-f0-9)" "terraform_${V}_linux_arm64.zip" \
            "${sha}" "${ZIPNAME}" > "${SRV}/${SUMS}"
        gpg --homedir "${WORK}/gh-$1" --batch --yes --pinentry-mode loopback --passphrase '' \
            --detach-sign -o "${SRV}/${SUMS}.sig" "${SRV}/${SUMS}" >/dev/null 2>&1
        gpg --homedir "${WORK}/gh-$2" --batch --armor --export > "${SRV}/pgp-key.txt" 2>/dev/null
    }
    zip_fetched() { grep -q "/${ZIPNAME}\$" "${FETCH_LOG}"; }
    bin_empty() { [[ -z "$(ls -A "${T_HOME}/.local/bin" 2>/dev/null)" ]]; }

    # 14. Good signature and checksum
    new_scenario; remember_scratch; serve_zip good good right
    out="$(TEST_FPR="${FPR_GOOD}" WORKBENCH_OS=Linux WORKBENCH_ARCH=x86_64 tf_run stub _tf-install-zip "${V}")"; rc=$?
    if [[ ${rc} -eq 0 && -x "${T_HOME}/.local/bin/terraform" && "$("${T_HOME}/.local/bin/terraform" version)" == "Terraform v${V}" ]] \
       && grep -q "releases.hashicorp.com/terraform/${V}/${ZIPNAME}\$" "${FETCH_LOG}" \
       && grep -q "www.hashicorp.com/.well-known/pgp-key.txt\$" "${FETCH_LOG}"; then
        ok "zip: good signature and SHA-256 install ~/.local/bin/terraform"
    else
        fail "zip good (rc=${rc}): ${out}"
    fi

    # 15. Signed by another key
    new_scenario; remember_scratch; serve_zip other good right
    out="$(TEST_FPR="${FPR_GOOD}" WORKBENCH_OS=Linux WORKBENCH_ARCH=x86_64 tf_run stub _tf-install-zip "${V}")"; rc=$?
    if [[ ${rc} -ne 0 && "${out}" == *"no good signature"* ]] && ! zip_fetched && bin_empty; then
        ok "zip: a bad signature refuses before the zip is downloaded; nothing in ~/.local/bin"
    else
        fail "zip bad signature (rc=${rc}): ${out}"
    fi

    # 16. Checksum mismatch
    new_scenario; remember_scratch; serve_zip good good wrong
    out="$(TEST_FPR="${FPR_GOOD}" WORKBENCH_OS=Linux WORKBENCH_ARCH=x86_64 tf_run stub _tf-install-zip "${V}")"; rc=$?
    if [[ ${rc} -ne 0 ]] && bin_empty; then
        ok "zip: a SHA-256 mismatch refuses; nothing in ~/.local/bin"
    else
        fail "zip sha mismatch (rc=${rc}): ${out}"
    fi

    # 17. Served release key isn't the pinned one
    new_scenario; remember_scratch; serve_zip other other right
    out="$(TEST_FPR="${FPR_GOOD}" WORKBENCH_OS=Linux WORKBENCH_ARCH=x86_64 tf_run stub _tf-install-zip "${V}")"; rc=$?
    if [[ ${rc} -ne 0 && "${out}" == *"served release key is not"* ]] && ! zip_fetched && bin_empty; then
        ok "zip: a served key without the pinned fingerprint refuses before the zip is downloaded"
    else
        fail "zip unpinned key (rc=${rc}): ${out}"
    fi

    # 18-21. The real Core API helpers, when a workbench-core checkout is here.
    if [[ -z "${CORE_LIB}" ]]; then
        echo "SKIP: no workbench-core checkout (WORKBENCH_CORE_DIR) — real-helper rpm/deb checks not run"
    else
        gpg --homedir "${WORK}/gh-good" --batch --armor --export > "${WORK}/good.asc" 2>/dev/null
        gpg --homedir "${WORK}/gh-other" --batch --armor --export > "${WORK}/other.asc" 2>/dev/null
        keys_in() { gpg --show-keys --with-colons "$1" 2>/dev/null | awk -F: 'p == "pub" && $1 == "fpr" { print $10 } { p = $1 }' | tr '\n' ' '; }

        new_scenario; remember_scratch; os_release 'ID=fedora'
        { cat "${WORK}/good.asc" "${WORK}/other.asc"; } > "${SRV}/gpg"
        out="$(TEST_FPR="${FPR_GOOD}" tf_run core _tf-install-rpm)"; rc=$?
        repo="${T_ROOT}/etc/yum.repos.d/workbench-hashicorp.repo"
        key="${T_ROOT}/etc/pki/rpm-gpg/RPM-GPG-KEY-workbench-workbench-hashicorp"
        if [[ ${rc} -eq 0 && "${out}" == *"PKG: dnf install -y terraform"* ]] \
           && grep -qx '\[workbench-hashicorp\]' "${repo}" \
           && grep -qx 'gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-workbench-workbench-hashicorp' "${repo}" \
           && grep -qx 'includepkgs=terraform' "${repo}" \
           && grep -qx 'baseurl=https://rpm.releases.hashicorp.com/fedora/$releasever/$basearch/stable' "${repo}" \
           && [[ "$(keys_in "${key}")" == "${FPR_GOOD} " ]]; then
            ok "rpm (core helpers): repo id workbench-hashicorp, gpgkey=file://, includepkgs=terraform, only the pinned key stored"
        else
            fail "rpm core (rc=${rc}): ${out} / repo: $(cat "${repo}" 2>/dev/null)"
        fi

        new_scenario; remember_scratch; os_release 'ID=fedora'
        cp "${WORK}/other.asc" "${SRV}/gpg"
        out="$(TEST_FPR="${FPR_GOOD}" tf_run core _tf-install-rpm)"; rc=$?
        if [[ ${rc} -ne 0 && "${out}" != *"PKG: dnf"* && ! -e "${T_ROOT}/etc/yum.repos.d/workbench-hashicorp.repo" ]]; then
            ok "rpm (core helpers): a served key without the pinned fingerprint refuses; no repo written"
        else
            fail "rpm core refusal (rc=${rc}): ${out}"
        fi

        new_scenario; remember_scratch; os_release 'ID=ubuntu' 'UBUNTU_CODENAME=jammy'
        { cat "${WORK}/good.asc" "${WORK}/other.asc"; } > "${SRV}/gpg"
        out="$(TEST_FPR="${FPR_GOOD}" tf_run core _tf-install-deb)"; rc=$?
        if [[ ${rc} -eq 0 && "${out}" == *"PKG: apt-get install -y terraform"* \
              && "$(keys_in "${T_ROOT}/usr/share/keyrings/workbench-hashicorp.gpg")" == "${FPR_GOOD} " \
              && "$(cat "${T_ROOT}/etc/apt/sources.list.d/workbench-hashicorp.list" 2>/dev/null)" == "${LIST_LINE}" ]]; then
            ok "deb (core helpers): keyring holds only the pinned key; list has signed-by"
        else
            fail "deb core (rc=${rc}): ${out}"
        fi

        new_scenario; remember_scratch; os_release 'ID=ubuntu' 'UBUNTU_CODENAME=jammy'
        cp "${WORK}/other.asc" "${SRV}/gpg"
        out="$(TEST_FPR="${FPR_GOOD}" tf_run core _tf-install-deb)"; rc=$?
        if [[ ${rc} -ne 0 && "${out}" != *"PKG: apt-get"* && ! -e "${T_ROOT}/etc/apt/sources.list.d/workbench-hashicorp.list" ]]; then
            ok "deb (core helpers): a served key without the pinned fingerprint refuses; no list written"
        else
            fail "deb core refusal (rc=${rc}): ${out}"
        fi
    fi
fi

# Last. Nothing was written to the working directory (H7)
dirty=""
for d in ${SCRATCH_DIRS}; do
    [[ -n "$(ls -A "${d}" 2>/dev/null)" ]] && dirty="${dirty} ${d}"
done
if [[ -z "${dirty}" ]]; then
    ok "every run left its working directory empty"
else
    fail "files written to the working directory:${dirty}"
fi

echo
echo "==============================="
echo "Total OK/FAIL checks: ${check_no}, failed: ${FAILED}"
echo "==============================="
exit "${FAILED}"
