#!/usr/bin/env bash
# shell/completions/terraform.sh — workbench-iac
# Terraform / OpenTofu shell completions. Registered at tier: tools
# (.dotfiles-sync.yml), sourced unconditionally; each block guards on
# `command -v`.
# Ported from workbench-precursor's completions/terraform.sh, unchanged.

if command -v tofu &>/dev/null; then
    if [[ -n "${BASH_VERSION}" ]]; then
        complete -C tofu tofu 2>/dev/null || true
    fi
fi

if command -v terraform &>/dev/null; then
    if [[ -n "${BASH_VERSION}" ]]; then
        complete -C terraform terraform 2>/dev/null || true
    fi
fi
