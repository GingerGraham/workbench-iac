#!/usr/bin/env bash
# shell/installers.sh — workbench-iac
# install-terraform, install-tenv, install-tflint, install-ansible and their
# per-distro helpers. Ported from workbench-precursor's lazy/installers-iac.sh
# (the Terraform/Ansible slice — that file split across Wave C modules, per
# the module map's own §7 call-out; the AWS/Azure/GCP and Helm slices live in
# workbench-cloud and workbench-containers respectively).
#
# WORKBENCH_OS/WORKBENCH_DISTRO/WORKBENCH_ARCH are workbench-core Core API
# platform facts (contracts/core-api.md), replacing the precursor's
# DOTFILES_OS/DOTFILES_DISTRO. _download_file_robust/_str_lower come from
# workbench-core's Core API.
#
# This file is self-contained on purpose: `wb tools update` sources only the
# single register.installers[].src file named in the manifest — never a
# module's register.shell[] files too (see bin/wb's _wb_tools_invoke in
# workbench-core) — so install-terraform below carries its own private
# version-lookup helper (_iac_latest_terraform_version) rather than calling
# shell/terraform.sh's interactive get-latest-terraform-version, which is
# not guaranteed to be loaded in that process.

_iac_latest_terraform_version() {
    curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform \
        | tr -d '\r' \
        | grep -Eo '"current_version":"[0-9]+\.[0-9]+\.[0-9]+"' \
        | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+'
}

# ── Ansible install ───────────────────────────────────────────────────────────
_ansible-install-dnf() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    [[ "${elevation_cmd}" == "run0" ]] && log_warn "run0 detected — multiple prompts expected"
    command -v dnf &>/dev/null || { log_error "dnf not found"; return 1; }
    log_info "Installing Ansible via dnf..."
    ${elevation_cmd} dnf install -y ansible
}

_ansible-install-yum() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    command -v yum &>/dev/null || { log_error "yum not found"; return 1; }
    ${elevation_cmd} yum install -y ansible
}

_ansible-install-zypper() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    command -v zypper &>/dev/null || { log_error "zypper not found"; return 1; }
    ${elevation_cmd} zypper install -y ansible
}

_ansible-install-pacman() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    command -v pacman &>/dev/null || { log_error "pacman not found"; return 1; }
    ${elevation_cmd} pacman -S --noconfirm ansible
}

_ansible-add-ppa() {
    local elevation_cmd; elevation_cmd="$(get-elevation-command)" || return 1
    command -v apt-add-repository &>/dev/null || { log_error "apt-add-repository not found"; return 1; }
    ${elevation_cmd} apt update
    dpkg -l | grep -q software-properties-common \
        || ${elevation_cmd} apt install -y software-properties-common
    ${elevation_cmd} apt-add-repository -y ppa:ansible/ansible
}

_ansible-install-python() {
    command -v pip3 &>/dev/null || { log_error "pip3 is required"; return 1; }
    local latest
    latest="$(curl -s https://pypi.org/pypi/ansible/json | grep -Eo '"version":"[0-9]+\.[0-9]+\.[0-9]+",' | sed -E 's/.+"([0-9]+\.[0-9]+\.[0-9]+)",/\1/' | head -1)"
    [[ -z "${latest}" ]] && { log_error "Could not determine latest Ansible version"; return 1; }
    log_info "Installing Ansible ${latest} via pip3..."
    pip3 install --upgrade ansible --disable-pip-version-check
}

install-ansible() {
    log_info "Installing Ansible..."
    [[ -z "${PACKAGE_MANAGER:-}" ]] && detect-package-manager
    case "${PACKAGE_MANAGER:-}" in
        dnf)    _ansible-install-dnf ;;
        yum)    _ansible-install-yum ;;
        zypper) _ansible-install-zypper ;;
        pacman) _ansible-install-pacman ;;
        apt)    _ansible-add-ppa && { local ec; ec="$(get-elevation-command)"; ${ec} apt install -y ansible; } ;;
        brew)   brew install ansible ;;
        *)      _ansible-install-python ;;
    esac
}

installed-ansible() {
    command -v ansible &>/dev/null
}

# ── Terraform install ─────────────────────────────────────────────────────────
_tf-install-linux() {
    local tf_version="${1:-$(_iac_latest_terraform_version)}"
    [[ -z "${tf_version}" ]] && { log_error "Could not determine Terraform version"; return 1; }

    if command -v terraform &>/dev/null; then
        local current
        current="$(terraform version | sed -r 's/Terraform v([0-9.]+)/\1/' | head -1)"
        [[ "${current}" == "${tf_version}" ]] && { log_info "Terraform ${tf_version} already installed"; return 0; }
    fi

    if command -v tfenv &>/dev/null; then
        git --git-dir="${HOME}/.tfenv/.git" pull && tfenv install "${tf_version}" && tfenv use "${tf_version}"
        return $?
    fi

    log_info "Installing tfenv..."
    git clone --depth=1 https://github.com/tfutils/tfenv.git "${HOME}/.tfenv" || { log_error "tfenv clone failed"; return 1; }
    [[ ":${PATH}:" != *":${HOME}/.tfenv/bin:"* ]] && PATH="${HOME}/.tfenv/bin:${PATH}"
    command -v tfenv &>/dev/null || { log_error "tfenv not found after install"; return 1; }
    tfenv install latest && tfenv use latest
}

_tf-install-mac() {
    local tf_version="${1:-$(_iac_latest_terraform_version)}"
    if command -v brew &>/dev/null; then
        if command -v tfenv &>/dev/null; then
            brew upgrade tfenv
        else
            brew install tfenv
        fi
    elif command -v git &>/dev/null; then
        git clone --depth=1 https://github.com/tfutils/tfenv.git "${HOME}/.tfenv"
        [[ ":${PATH}:" != *":${HOME}/.tfenv/bin:"* ]] && PATH="${HOME}/.tfenv/bin:${PATH}"
    else
        log_error "Neither brew nor git found"; return 1
    fi
    tfenv install latest && tfenv use latest
}

# install-tflint is this same module's own installer (below); install-trivy
# is workbench-security's — a soft dependency, only called if that module is
# also registered and its installer already loaded in this process.
install-terraform() {
    local tf_version
    tf_version="$(_iac_latest_terraform_version)"
    [[ -z "${tf_version}" ]] && { log_error "Could not determine Terraform version"; return 1; }
    case "${WORKBENCH_OS}" in
        Linux) _tf-install-linux "${tf_version}" ;;
        Mac)   _tf-install-mac "${tf_version}" ;;
        *)     log_error "Unsupported OS"; return 1 ;;
    esac || return 1

    install-tflint
    if command -v install-trivy &>/dev/null; then
        install-trivy
    else
        log_info "install-trivy not available (workbench-security not installed?) — skipping trivy scan tooling"
    fi
}

installed-terraform() {
    command -v terraform &>/dev/null
}

# ── tenv install (OpenTofu / Terraform version manager) ───────────────────────
# Upstream: https://github.com/tofuutils/tenv
# Release artifacts are cosign-signed. We verify the checksums file and the asset
# with cosign when it's present, then always confirm the SHA256. Without cosign
# we fall back to SHA256-only (set TENV_INSTALL_REQUIRE_COSIGN=true to make
# cosign mandatory).

# Extract a browser_download_url whose filename matches an extended regex.
_tenv_asset_url() {
    local api_json="$1" pattern="$2"
    printf '%s' "${api_json}" \
        | grep -Eo '"browser_download_url": *"[^"]+"' \
        | sed -E 's/.*"(https[^"]+)"/\1/' \
        | grep -E "${pattern}" \
        | head -1
}

# cosign keyless verification of a blob against its detached sig + certificate.
_tenv_cosign_verify() {
    # $1 file  $2 sig  $3 pem  $4 tag
    cosign verify-blob \
        --certificate-identity "https://github.com/tofuutils/tenv/.github/workflows/release.yml@refs/tags/$4" \
        --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
        --signature "$2" \
        --certificate "$3" \
        "$1"
}

# Download asset + checksums (+ sigs/pems) into $1, verify, and on success set
# _TENV_VERIFIED_ASSET to the verified asset path. Returns non-zero on any
# verification failure. (Path is returned via a variable, not stdout, so logger
# output can't contaminate it.)
_tenv_fetch_and_verify() {
    local tmp="$1" tag="$2" asset_pattern="$3" api_json="$4"
    _TENV_VERIFIED_ASSET=""

    local asset_url sig_url pem_url sums_url sums_sig_url sums_pem_url
    asset_url="$(_tenv_asset_url     "${api_json}" "${asset_pattern}\$")"
    sig_url="$(_tenv_asset_url       "${api_json}" "${asset_pattern}\.sig\$")"
    pem_url="$(_tenv_asset_url       "${api_json}" "${asset_pattern}\.pem\$")"
    sums_url="$(_tenv_asset_url      "${api_json}" "_checksums\.txt\$")"
    sums_sig_url="$(_tenv_asset_url  "${api_json}" "_checksums\.txt\.sig\$")"
    sums_pem_url="$(_tenv_asset_url  "${api_json}" "_checksums\.txt\.pem\$")"

    [[ -z "${asset_url}" ]] && { log_error "tenv: no asset matching /${asset_pattern}/ in ${tag}"; return 1; }
    [[ -z "${sums_url}"  ]] && { log_error "tenv: checksums file not found in ${tag}"; return 1; }

    local asset; asset="$(basename "${asset_url}")"
    log_info "tenv: downloading ${asset} ..."
    _download_file_robust "${asset_url}" "${tmp}/${asset}"                   || return 1
    _download_file_robust "${sums_url}"  "${tmp}/$(basename "${sums_url}")"  || return 1

    if command -v cosign &>/dev/null; then
        if [[ -n "${sig_url}" && -n "${pem_url}" && -n "${sums_sig_url}" && -n "${sums_pem_url}" ]]; then
            _download_file_robust "${sig_url}"      "${tmp}/$(basename "${sig_url}")"      || return 1
            _download_file_robust "${pem_url}"      "${tmp}/$(basename "${pem_url}")"      || return 1
            _download_file_robust "${sums_sig_url}" "${tmp}/$(basename "${sums_sig_url}")" || return 1
            _download_file_robust "${sums_pem_url}" "${tmp}/$(basename "${sums_pem_url}")" || return 1

            log_info "tenv: verifying checksums signature with cosign ..."
            ( cd "${tmp}" && _tenv_cosign_verify \
                "$(basename "${sums_url}")" "$(basename "${sums_sig_url}")" "$(basename "${sums_pem_url}")" "${tag}" ) \
                || { log_error "tenv: cosign verification of checksums failed"; return 1; }

            log_info "tenv: verifying ${asset} signature with cosign ..."
            ( cd "${tmp}" && _tenv_cosign_verify \
                "${asset}" "$(basename "${sig_url}")" "$(basename "${pem_url}")" "${tag}" ) \
                || { log_error "tenv: cosign verification of ${asset} failed"; return 1; }
        else
            log_warn "tenv: cosign present but signature assets missing for ${tag} — skipping cosign step"
        fi
    elif [[ "${TENV_INSTALL_REQUIRE_COSIGN:-false}" == "true" ]]; then
        log_error "tenv: cosign required (TENV_INSTALL_REQUIRE_COSIGN=true) but not installed. Run install-cosign (workbench-security)."
        return 1
    else
        log_warn "tenv: cosign not installed — SHA256-only verification. Run install-cosign (workbench-security) for signature checks."
    fi

    log_info "tenv: verifying SHA256 checksum ..."
    ( cd "${tmp}" && sha256sum -c "$(basename "${sums_url}")" --ignore-missing ) \
        || { log_error "tenv: SHA256 verification failed"; return 1; }

    _TENV_VERIFIED_ASSET="${tmp}/${asset}"
    return 0
}

_tenv-install-rpm() {
    local tag="$1" api_json="$2" arch
    case "${WORKBENCH_ARCH}" in
        x86_64|amd64)  arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) log_error "tenv: unsupported architecture ${WORKBENCH_ARCH}"; return 1 ;;
    esac
    local tmp; tmp="$(mktemp -d)"
    _tenv_fetch_and_verify "${tmp}" "${tag}" "tenv_${tag}_${arch}\.rpm" "${api_json}" \
        || { rm -rf "${tmp}"; return 1; }
    local ec; ec="$(get-elevation-command)" || { rm -rf "${tmp}"; return 1; }
    log_info "tenv: installing $(basename "${_TENV_VERIFIED_ASSET}") ..."
    if command -v dnf &>/dev/null; then
        ${ec} dnf install -y "${_TENV_VERIFIED_ASSET}"
    elif command -v zypper &>/dev/null; then
        # rpm is already cosign-verified by us; zypper's own GPG check is moot here.
        ${ec} zypper --non-interactive install --allow-unsigned-rpm "${_TENV_VERIFIED_ASSET}"
    else
        ${ec} yum install -y "${_TENV_VERIFIED_ASSET}"
    fi
    local rc=$?; rm -rf "${tmp}"; return $rc
}

_tenv-install-deb() {
    local tag="$1" api_json="$2" arch
    case "${WORKBENCH_ARCH}" in
        x86_64|amd64)  arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) log_error "tenv: unsupported architecture ${WORKBENCH_ARCH}"; return 1 ;;
    esac
    local tmp; tmp="$(mktemp -d)"
    _tenv_fetch_and_verify "${tmp}" "${tag}" "tenv_${tag}_${arch}\.deb" "${api_json}" \
        || { rm -rf "${tmp}"; return 1; }
    local ec; ec="$(get-elevation-command)" || { rm -rf "${tmp}"; return 1; }
    log_info "tenv: installing $(basename "${_TENV_VERIFIED_ASSET}") ..."
    ${ec} dpkg -i "${_TENV_VERIFIED_ASSET}" || ${ec} apt-get install -f -y
    local rc=$?; rm -rf "${tmp}"; return $rc
}

_tenv-install-arch() {
    local tag="$1" api_json="$2"
    local tmp; tmp="$(mktemp -d)"
    _tenv_fetch_and_verify "${tmp}" "${tag}" "tenv_${tag}_.*\.pkg\.tar\.zst" "${api_json}" \
        || { rm -rf "${tmp}"; return 1; }
    local ec; ec="$(get-elevation-command)" || { rm -rf "${tmp}"; return 1; }
    log_info "tenv: installing $(basename "${_TENV_VERIFIED_ASSET}") ..."
    ${ec} pacman -U --noconfirm "${_TENV_VERIFIED_ASSET}"
    local rc=$?; rm -rf "${tmp}"; return $rc
}

# Generic fallback: extract binaries to ~/.local/bin (root-free). Matches loosely
# on _Linux_*.tar.gz to stay robust to the goreleaser arch token (x86_64 vs amd64).
_tenv-install-tarball() {
    local tag="$1" api_json="$2"
    local tmp; tmp="$(mktemp -d)"
    _tenv_fetch_and_verify "${tmp}" "${tag}" "tenv_${tag}_Linux_.*\.tar\.gz" "${api_json}" \
        || { rm -rf "${tmp}"; return 1; }
    log_info "tenv: extracting to ~/.local/bin ..."
    mkdir -p "${HOME}/.local/bin"
    tar -xzf "${_TENV_VERIFIED_ASSET}" -C "${tmp}" \
        || { log_error "tenv: extraction failed"; rm -rf "${tmp}"; return 1; }
    local b
    for b in tenv tofu terraform tf tg tm at terragrunt terramate atmos; do
        [[ -f "${tmp}/${b}" ]] && { cp "${tmp}/${b}" "${HOME}/.local/bin/${b}"; chmod +x "${HOME}/.local/bin/${b}"; }
    done
    rm -rf "${tmp}"
    command -v tenv &>/dev/null || { log_error "tenv: not on PATH after install (is ~/.local/bin on PATH?)"; return 1; }
}

install-tenv() {
    log_info "Installing or updating tenv (OpenTofu / Terraform version manager)..."
    command -v curl &>/dev/null || { log_error "curl is required"; return 1; }

    if [[ "${WORKBENCH_OS}" == "Mac" ]]; then
        command -v brew &>/dev/null || { log_error "brew is required on macOS"; return 1; }
        if brew list tenv &>/dev/null; then brew upgrade tenv; else brew install tenv; fi
        return $?
    fi

    local api_json tag
    api_json="$(curl -fsSL https://api.github.com/repos/tofuutils/tenv/releases/latest)" \
        || { log_error "tenv: could not query release API"; return 1; }
    tag="$(printf '%s' "${api_json}" | grep -E '"tag_name":' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')"
    [[ -z "${tag}" ]] && { log_error "tenv: could not determine latest version"; return 1; }
    log_info "tenv: latest release is ${tag}"

    if command -v tenv &>/dev/null; then
        local current; current="$(tenv version 2>/dev/null | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
        if [[ "${current}" == "${tag}" ]]; then
            log_info "tenv ${tag} already installed"; return 0
        fi
        log_info "tenv: updating ${current:-unknown} → ${tag}"
    fi

    [[ -z "${PACKAGE_MANAGER:-}" ]] && detect-package-manager

    case "${PACKAGE_MANAGER:-}" in
        dnf|yum)  _tenv-install-rpm     "${tag}" "${api_json}" ;;
        zypper)   _tenv-install-rpm     "${tag}" "${api_json}" ;;
        apt)      _tenv-install-deb     "${tag}" "${api_json}" ;;
        pacman)   _tenv-install-arch    "${tag}" "${api_json}" ;;
        *)        _tenv-install-tarball "${tag}" "${api_json}" ;;
    esac
    local rc=$?

    if [[ $rc -eq 0 ]] && command -v tenv &>/dev/null; then
        log_info "tenv installed: $(tenv version 2>/dev/null | head -1)"
        log_info "Set TENV_AUTO_INSTALL=true in ~/.config/workbench/local/settings.sh if you want tofu/terraform versions to install on first use."
        command -v cosign &>/dev/null \
            || log_warn "cosign not present: tenv falls back to PGP/SHA for tofu & terraform checks. Run install-cosign (workbench-security) for full cosign verification."
    fi
    return $rc
}

installed-tenv() {
    command -v tenv &>/dev/null
}

# ── TFLint install ────────────────────────────────────────────────────────────
_tflint-install-linux() {
    local ver
    ver="$(curl -s https://api.github.com/repos/terraform-linters/tflint/releases/latest \
        | grep '"tag_name":' | sed -E 's/.+"v([^"]+)".+/\1/')"
    [[ -z "${ver}" ]] && { log_error "Could not determine TFLint version"; return 1; }

    if command -v tflint &>/dev/null; then
        local current
        current="$(tflint --version | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
        [[ "${current}" == "${ver}" ]] && { log_info "TFLint ${ver} already installed"; return 0; }
    fi

    command -v unzip &>/dev/null || { log_error "unzip required for TFLint install"; return 1; }

    local install_path="${HOME}/.local/bin/tf-lint/tflint-${ver}"
    mkdir -p "${install_path}"
    TFLINT_INSTALL_PATH="${install_path}" \
        bash <(curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh)

    [[ -x "${install_path}/tflint" ]] || { log_error "TFLint install failed"; return 1; }

    local existing; existing="$(command -v tflint 2>/dev/null)"
    if [[ -n "${existing}" ]]; then
        if [[ -L "${existing}" ]]; then
            rm "${existing}"
        else
            mv "${existing}" "${existing}.old"
        fi
    fi
    ln -sf "${install_path}/tflint" "${HOME}/.local/bin/tflint"
    log_info "TFLint ${ver} installed"
}

_tflint-install-mac() {
    local ver
    ver="$(curl -s https://api.github.com/repos/terraform-linters/tflint/releases/latest \
        | grep '"tag_name":' | sed -E 's/.+"v([^"]+)".+/\1/')"
    [[ -z "${ver}" ]] && { log_error "Could not determine TFLint version"; return 1; }

    command -v brew &>/dev/null || { log_error "brew required on macOS"; return 1; }
    if command -v tflint &>/dev/null; then
        brew upgrade tflint
    else
        brew install tflint
    fi
}

install-tflint() {
    case "${WORKBENCH_OS}" in
        Linux) _tflint-install-linux ;;
        Mac)   _tflint-install-mac ;;
        *)     log_error "Unsupported OS for tflint"; return 1 ;;
    esac
}

installed-tflint() {
    command -v tflint &>/dev/null
}
