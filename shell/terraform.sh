#!/usr/bin/env bash
# shell/terraform.sh — workbench-iac
# Terraform / OpenTofu / Terragrunt tool configuration. Registered at
# tier: tools (workbench.yml), sourced unconditionally; individual
# alias blocks guard on `command -v`.
# Ported from workbench-precursor's tools/terraform.sh, unchanged.

# ── aliases ───────────────────────────────────────────────────────────────────
if command -v tofu &>/dev/null; then
    # OpenTofu (preferred when both installed)
    workbench_alias_define tf iac "tofu"
    workbench_alias_define tfi iac "tofu init"
    workbench_alias_define tfp iac "tofu plan"
    workbench_alias_define tfpd iac "tofu plan -destroy"
    workbench_alias_define tfa iac "tofu apply"
    workbench_alias_define tfaa iac "tofu apply -auto-approve"
    workbench_alias_define tfd iac "tofu destroy"
    workbench_alias_define tfr iac "tofu refresh"
    workbench_alias_define tfsh iac "tofu show"
    workbench_alias_define tfsl iac "tofu state list"
    workbench_alias_define tfo iac "tofu output"
    workbench_alias_define tfv iac "tofu version"
    workbench_alias_define tffmt iac "tofu fmt"
    workbench_alias_define tfva iac "tofu validate"
    workbench_alias_define tfws iac "tofu workspace"

    workbench_alias_define otf iac "tofu"
    workbench_alias_define otfi iac "tofu init"
    workbench_alias_define otfp iac "tofu plan"
    workbench_alias_define otfpd iac "tofu plan -destroy"
    workbench_alias_define otfa iac "tofu apply"
    workbench_alias_define otfaa iac "tofu apply -auto-approve"
    workbench_alias_define otfd iac "tofu destroy"
    workbench_alias_define otfr iac "tofu refresh"
    workbench_alias_define otfsh iac "tofu show"
    workbench_alias_define otfsl iac "tofu state list"
    workbench_alias_define otfo iac "tofu output"
    workbench_alias_define otfv iac "tofu version"
    workbench_alias_define otffmt iac "tofu fmt"
    workbench_alias_define otfva iac "tofu validate"
    workbench_alias_define otfws iac "tofu workspace"
fi

if command -v terraform &>/dev/null; then
    # tf* only when OpenTofu is absent
    if ! command -v tofu &>/dev/null; then
        workbench_alias_define tf iac "terraform"
        workbench_alias_define tfi iac "terraform init"
        workbench_alias_define tfp iac "terraform plan"
        workbench_alias_define tfpd iac "terraform plan -destroy"
        workbench_alias_define tfa iac "terraform apply"
        workbench_alias_define tfaa iac "terraform apply -auto-approve"
        workbench_alias_define tfd iac "terraform destroy"
        workbench_alias_define tfr iac "terraform refresh"
        workbench_alias_define tfsh iac "terraform show"
        workbench_alias_define tfsl iac "terraform state list"
        workbench_alias_define tfo iac "terraform output"
        workbench_alias_define tfv iac "terraform version"
        workbench_alias_define tffmt iac "terraform fmt"
        workbench_alias_define tfva iac "terraform validate"
        workbench_alias_define tfws iac "terraform workspace"
    fi

    workbench_alias_define hctf iac "terraform"
    workbench_alias_define hctfi iac "terraform init"
    workbench_alias_define hctfp iac "terraform plan"
    workbench_alias_define hctfpd iac "terraform plan -destroy"
    workbench_alias_define hctfa iac "terraform apply"
    workbench_alias_define hctfaa iac "terraform apply -auto-approve"
    workbench_alias_define hctfd iac "terraform destroy"
    workbench_alias_define hctfr iac "terraform refresh"
    workbench_alias_define hctfsh iac "terraform show"
    workbench_alias_define hctfsl iac "terraform state list"
    workbench_alias_define hctfo iac "terraform output"
    workbench_alias_define hctfv iac "terraform version"
    workbench_alias_define hctffmt iac "terraform fmt"
    workbench_alias_define hctfva iac "terraform validate"
    workbench_alias_define hctfws iac "terraform workspace"
fi

if command -v terragrunt &>/dev/null; then
    workbench_alias_define tg iac "terragrunt"
    workbench_alias_define tgi iac "terragrunt init"
    workbench_alias_define tgp iac "terragrunt plan"
    workbench_alias_define tgpd iac "terragrunt plan -destroy"
    workbench_alias_define tga iac "terragrunt apply"
    workbench_alias_define tgaa iac "terragrunt apply -auto-approve"
    workbench_alias_define tgd iac "terragrunt destroy"
    workbench_alias_define tgr iac "terragrunt refresh"
    workbench_alias_define tgo iac "terragrunt output"
    workbench_alias_define tgv iac "terragrunt version"
    workbench_alias_define tgfmt iac "terragrunt fmt"
    workbench_alias_define tgva iac "terragrunt validate"
    workbench_alias_define tgws iac "terragrunt workspace"
fi

# ── availability gating ─────────────────────────────────────────────────────
# Function availability predicates — consumed automatically by
# _get_functions_in/_get_aliases_in (workbench-core) to hide aliases that
# can't actually be used on this host. See workbench-core's
# docs/guide/module-authoring.md, "Declaring function availability".
#
# otf*/hctf*/tg* are only ever defined once their own `command -v` guard
# above has passed, but the get-iac-functions listing (generated by
# workbench-core from this module's manifest) reads the files statically
# and can't see that runtime guard, so without these it would list them
# even on hosts missing the underlying tool. Declare their availability
# predicates so the listing matches reality.
#
# tofu and terragrunt come from tenv (wb tools install tenv); terraform from
# install-terraform or tenv.
_iac_tofu_present()       { command -v tofu &>/dev/null; }
_iac_terragrunt_present() { command -v terragrunt &>/dev/null; }
_wb_alias_availability --needs "tofu (OpenTofu)" --install tenv _iac_tofu_present \
    otf otfi otfp otfpd otfa otfaa otfd otfr otfsh otfsl otfo otfv otffmt otfva otfws
_wb_declare_availability terraform hctf hctfi hctfp hctfpd hctfa hctfaa hctfd hctfr hctfsh hctfsl hctfo hctfv hctffmt hctfva hctfws
_wb_alias_availability --needs "terragrunt" --install tenv _iac_terragrunt_present \
    tg tgi tgp tgpd tga tgaa tgd tgr tgo tgv tgfmt tgva tgws

# tf*/otf's short aliases above fall back between OpenTofu and Terraform
# (OpenTofu preferred when both are installed — see the alias blocks
# above), so they still work with just one of the two present; only
# genuinely unusable when neither is installed.
_iac_tf_present() {
    command -v tofu &>/dev/null || command -v terraform &>/dev/null
}
_wb_alias_availability --needs "tofu or terraform" --install tenv _iac_tf_present \
    tf tfi tfp tfpd tfa tfaa tfd tfr tfsh tfsl tfo tfv tffmt tfva tfws

# ── functions ─────────────────────────────────────────────────────────────────
get-latest-terraform-version() {
    local json version
    json="$(curl -fsS --connect-timeout 30 --max-time 60 https://checkpoint-api.hashicorp.com/v1/check/terraform)" \
        || { log_error "Could not query HashiCorp for the latest Terraform version (network or HTTP error)"; return 1; }
    version="$(printf '%s' "${json}" | tr -d '\r' \
        | grep -Eo '"current_version":"[0-9]+\.[0-9]+\.[0-9]+"' \
        | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    [[ -z "${version}" ]] && { log_error "Could not determine the latest Terraform version"; return 1; }
    printf '%s\n' "${version}"
}

get-latest-opentofu-version() {
    local json version
    json="$(curl -fsS --connect-timeout 30 --max-time 60 https://api.github.com/repos/opentofu/opentofu/releases/latest)" \
        || { log_error "Could not query GitHub for the latest OpenTofu version (network, HTTP error or API rate limit)"; return 1; }
    version="$(printf '%s' "${json}" | tr -d '\r' \
        | grep -Eo '"tag_name": ?"v[0-9]+\.[0-9]+\.[0-9]+"' \
        | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    [[ -z "${version}" ]] && { log_error "Could not determine the latest OpenTofu version"; return 1; }
    printf '%s\n' "${version}"
}
