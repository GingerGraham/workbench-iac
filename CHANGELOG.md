# Changelog

All notable changes to `workbench-iac` are documented here.

## [Unreleased]

### Added

- **Manual `workflow_dispatch` release override.** `release.yml` now
  accepts a `bump_type` (patch/minor/major) input to force a release
  through `workbench-core`'s reusable `module-release.yml`, regardless of
  what Conventional Commits since the last tag would compute — a floor,
  never a downgrade of a higher severity already pending. Manual dispatch
  only runs from `main`. See `workbench-core`'s `docs/decisions-log.md` D67.

## [0.2.1] - 2026-09-16

### Fixed

- `get-iac-functions`/`wb functions` no longer list Terraform/OpenTofu/
  Terragrunt aliases or `ansible-vault-decrypt`/`ansible-vault-encrypt`
  (and `ap`/`avd`/`ave`) on hosts missing the underlying tool. These
  were already self-gated at definition time (each block/file guards
  itself on `command -v`), but the listing's static-grep extraction
  couldn't see that runtime guard, so it showed them anyway. Declares
  `_<name>-available` predicates (`_wb_declare_availability` for the
  `otf*`/`hctf*`/`tg*`/`ansible-*` families, a hand-written OR predicate
  for `tf*`'s OpenTofu-or-Terraform fallback aliases) per
  `workbench-core`'s module-authoring.md "Declaring function
  availability" convention.

### Added

- **Agent-instruction files** (`AGENTS.md`, `CLAUDE.md`,
  `.github/copilot-instructions.md`,
  `.claude/skills/conventional-commits/SKILL.md`) — ports
  `workbench-core`'s D32 agent-instruction topology to this repo. See
  `workbench-core`'s `docs/decisions-log.md` D58.
- **Repo governance files** (`.github/PULL_REQUEST_TEMPLATE.md`,
  `.github/ISSUE_TEMPLATE/{bug_report,feature_request,config}.yml`,
  `.github/CODEOWNERS`, `CONTRIBUTING.md`, `SECURITY.md`) — ports
  `workbench-core`'s D31 governance-file topology to this repo,
  piloted on `workbench-git` first. See `workbench-core`'s
  `docs/decisions-log.md` D60.

## [0.2.0] - 2026-09-09

### Added

- Added `installed-ansible`, `installed-terraform`, `installed-tenv`,
  `installed-tflint` — reports install status to `wb tools upgrade`/
  `wb tools list --status` (workbench-core §12 D43).

## [0.1.0] - 2026-09-09

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

### Fixed

- `avd`/`ave` aliases now target the `ansible-vault-decrypt`/
  `ansible-vault-encrypt` wrapper functions instead of raw `ansible-vault
  decrypt`/`encrypt` — previously the aliases bypassed the wrappers'
  `vault_password_file`/`-p` handling entirely, while the `command -v`
  guards gating the aliases checked those same always-defined wrappers.
