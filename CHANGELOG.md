# Changelog

All notable changes to `workbench-iac` are documented here.

## [Unreleased]

### Added

- Initial decomposition from `workbench-precursor` (Wave C): Terraform/
  OpenTofu/Terragrunt aliases, `ansible-vault-decrypt`/`ansible-vault-encrypt`,
  Terraform shell completions, and `install-terraform`/`install-tenv`/
  `install-tflint`/`install-ansible`, split out of the precursor's grab-bag
  `installers-iac.sh`.

### Changed

- `install-terraform` no longer calls the precursor's shared
  `get-latest-terraform-version` (a `shell/terraform.sh` interactive-shell
  function) — `wb tools update` only sources a module's declared
  `register.installers[].src` file, never its `register.shell[]` files, so
  a cross-file call like that would fail outside an interactive shell that
  happened to have `terraform.sh` already loaded. `shell/installers.sh` now
  carries its own private `_iac_latest_terraform_version` copy.
- `install-trivy` (called by `install-terraform`) is now a guarded soft
  dependency on `workbench-security` (`command -v` check) rather than an
  unconditional call.
- `WORKBENCH_OS`/`WORKBENCH_DISTRO`/`WORKBENCH_ARCH` replace
  `DOTFILES_OS`/`DOTFILES_DISTRO`.
