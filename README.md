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

`install-tenv` recommends cosign (`wb tools install cosign`, from
`workbench-security`) for release-signature verification. It is not a hard
`core_api:` dependency — the installer checks for cosign with `command -v`.
`install-terraform` also installs `tflint` (this module).

## What `install-terraform` verifies

`wb tools install terraform` installs terraform from HashiCorp's own signed
packages. workbench no longer installs or manages tfenv.

| Host | Route | What is verified |
|---|---|---|
| Fedora, RHEL and rebuilds (`dnf`/`yum`) | HashiCorp's rpm repository, written as `/etc/yum.repos.d/workbench-hashicorp.repo` | The package key is pinned (`D55C 0D1A C78A 8D81 26CB 631C FC9C A96A CA02 6560`) and stored locally (`gpgkey=file://`), so dnf checks every package against it and never imports another key. The repository is limited to `terraform` (`includepkgs`). |
| Debian, Ubuntu and derivatives (`apt`) | HashiCorp's apt repository, `/etc/apt/sources.list.d/workbench-hashicorp.list` | `signed-by=` a keyring holding only the pinned package key, so apt checks the repository's signed metadata against it. |
| macOS with Homebrew | `brew install hashicorp/tap/terraform` | Homebrew checks the download against the SHA-256 in HashiCorp's tap formula. (homebrew-core's `terraform` is frozen at an old version.) |
| openSUSE, Arch, other Linux, macOS without Homebrew | The release zip, into `~/.local/bin/terraform` | `terraform_<version>_SHA256SUMS` must carry a good signature (`gpgv`) from the pinned release key (`C874 011F 0AB4 0511 0D02 1055 3436 5D94 72D7 468F`), and the zip must match its line there. Needs `gpg`, `gpgv` and `unzip`. Nothing is installed unless every step passes. |

If HashiCorp's own repository is already configured (`hashicorp.repo`, or a
source list for `apt.releases.hashicorp.com`), `install-terraform` uses it as
it is and writes nothing of its own.

**tenv is the alternative** (`wb tools install tenv`), for switching between
terraform and OpenTofu versions. Installing both means two programs provide
`terraform`; the one earlier on your `PATH` runs. If you still have tfenv
in `~/.tfenv`, its shim shadows this install while `~/.tfenv/bin` is on
`PATH`: remove `~/.tfenv`, or keep using tfenv yourself. workbench never
touches it.

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
