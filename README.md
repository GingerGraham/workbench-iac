# workbench-iac

Terraform / OpenTofu / Terragrunt / Ansible aliases and installers for the
[`workbench`](https://github.com/GingerGraham/workbench-core) ecosystem.

An **ecosystem module** (`workbench-core` ARCHITECTURE.md §2) — meaningless
standalone. Requires `workbench-core` installed first:

```sh
wb add iac
```

## What this gives you

- `tf*`/`otf*`/`hctf*` aliases (OpenTofu preferred over Terraform when both
  are installed; `hctf*` always targets Terraform specifically) and `tg*`
  aliases for Terragrunt.
- `get-latest-terraform-version`/`get-latest-opentofu-version`.
- `ansible-vault-decrypt`/`ansible-vault-encrypt` (honour `ansible.cfg`'s
  `vault_password_file` when present) and `ap`/`avd`/`ave` aliases.
- Terraform/OpenTofu shell completions.
- `install-terraform`, `install-tenv`, `install-tflint`, `install-ansible` —
  via `wb tools update`.

## Soft dependency on workbench-security

`install-terraform` calls `install-tflint` (this module) and, if present,
`install-trivy` (`workbench-security`) for scan tooling. `install-tenv`
recommends `install-cosign` (`workbench-security`) for full release-signature
verification, falling back to SHA256-only checksums without it. Neither is a
hard `core_api:` dependency — both are guarded with `command -v` checks.

## Requires

Nothing at install time — each tool is installed via its own
`install-<name>` function (`wb tools update`).
