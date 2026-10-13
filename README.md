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

## What `install-tenv` verifies

Release assets are always checked against the release's `*_checksums.txt`.
With `install-cosign` present and the release carrying signature assets, the
checksums file and the asset are also verified with cosign (keyless, pinned
to tenv's release identity). Set `TENV_INSTALL_REQUIRE_COSIGN=true` to make
missing cosign or missing signature assets a hard error on every distro.

**Cosign is required for the package-based installs.** A local package handed
to the package manager is not signature-checked against a trusted key, so
`install-tenv` refuses to install a downloaded `.rpm` (`dnf`, `yum`, `zypper`)
or `.deb` (`apt`/`dpkg`) unless cosign verified it, and tells you to run
`install-cosign` (`workbench-security`) first. The reasons, per path:

| Path | Package-manager signature check of a local file |
|---|---|
| Fedora/RHEL (`dnf`, `yum`) `.rpm` | **None by default** — `localpkg_gpgcheck` defaults to `0`, and `gpgcheck` only covers repository packages |
| openSUSE (`zypper`) `.rpm` | Rejects an unsigned or untrusted local RPM, so `--allow-unsigned-rpm` is needed after cosign verification |
| Debian/Ubuntu (`apt`/`dpkg`) `.deb` | None for a local file |

The Arch (`pacman -U`) and generic tarball fallbacks are not gated; they are
verified by the checksums file, plus cosign when it is installed.

No tenv package-signing key is pinned by this module, so there is no
`rpm -K`/`--checksig` step.

## Requires

Nothing at install time — each tool is installed via its own
`install-<name>` function (`wb tools update`).
