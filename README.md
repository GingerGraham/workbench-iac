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
  run with `wb tools install <name>` (for example `wb tools install tenv`),
  or `wb tools upgrade <name>` to update one already installed.

## Soft dependency on workbench-security

`install-terraform` calls `install-tflint` (this module) and, if present,
`install-trivy` (`workbench-security`) for scan tooling. `install-tenv`
recommends cosign (`wb tools install cosign`, from `workbench-security`) for
release-signature verification. Neither is a hard `core_api:` dependency —
both are guarded with `command -v` checks.

## What `install-tenv` verifies

Release assets are always checked against their own line in the release's
`*_checksums.txt`. With cosign present and the release carrying signature
assets, the checksums file and the asset are also verified with cosign
(keyless, pinned to tenv's release identity). A cosign verification that
fails always stops the install.

**Packages are installed as root only once cosign has verified them.** A
local package handed to the package manager is not signature-checked
against a trusted key:

| Path | Package-manager signature check of a local file |
|---|---|
| Fedora/RHEL (`dnf`, `yum`) `.rpm` | **None by default** — `localpkg_gpgcheck` defaults to `0`, and `gpgcheck` only covers repository packages |
| openSUSE (`zypper`) `.rpm` | Rejects an unsigned or untrusted local RPM, so `--allow-unsigned-rpm` is needed after cosign verification |
| Debian/Ubuntu (`apt`/`dpkg`) `.deb` | None for a local file |

So without cosign, `install-tenv` on those distros does not install the
`.rpm`/`.deb`. It installs the release tarball into `~/.local/bin` instead —
no root, SHA-256 checked, not signature-verified — and warns, saying to run
`wb tools install cosign` and then `wb tools install tenv` again for the
signed package. `~/.local/bin` needs to be on your `PATH`.

Set `TENV_INSTALL_REQUIRE_COSIGN=true` to refuse anything cosign hasn't
verified, on every distro: no tarball fallback, and missing cosign or
missing signature assets is an error.

The Arch (`pacman -U`) and generic tarball paths are verified by the
checksums file, plus cosign when it is installed. The tarball is the one
for this machine's architecture (`x86_64` or `arm64`).

No tenv package-signing key is pinned by this module, so there is no
`rpm -K`/`--checksig` step.

## Requires

Nothing at install time — each tool is installed on demand with
`wb tools install <name>`.
