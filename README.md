# urunc FreeBSD lab

Personal test bench for [urunc-dev/urunc#1108](https://github.com/urunc-dev/urunc/issues/1108)
(FreeBSD docs and rootfs filesystem detection). It runs on GitHub-hosted
`ubuntu-22.04` runners, which expose `/dev/kvm`, using the same setup as
urunc's own `.github/workflows/vm_test.yml`. Nothing here is part of the
urunc pull request.

## What a run does

| Job | What it checks |
|---|---|
| `checks` | `make unittest`, golangci-lint v2.9, cspell and commitlint on the branch under test, with urunc's own configs |
| `e2e` | upstream FreeBSD e2e cases (nerdctl: 9pfs + devmapper, docker: block) in default and libcontainer mode |
| `ext2-boot` | boots the caddy FreeBSD block image with its original UFS2 rootfs and with an ext2 copy, on QEMU and Firecracker, for both the base and the fix |
| `timing` | `TS01→TS02` (create) and `TS11→TS18` (start) for base and fix on the same runner, warm and cold page cache |

Expected `ext2-boot` results:

| | ufs | ext2 |
|---|---|---|
| base (upstream main) | boots | does not boot (`ufs` is passed for an ext2 disk) |
| fix | boots | boots |

## Running it

Actions → "urunc FreeBSD lab" → Run workflow, and set `fix_ref` to the branch
of `yug105/urunc` to test. Results are in the run summary; logs and
timestamp files are uploaded as artifacts.

## How the ext2 image is made

`scripts/make-ext2-image.sh` takes the FreeBSD tree of
`caddy-<monitor>-freebsd-raw`, builds an ext2 image from it with
`mkfs.ext2 -d`, and copies it over `/.boot/rootfs` of
`caddy-<monitor>-freebsd-block`. Both upstream images ship the same kernel
(it has EXT2FS, which the devmapper e2e case relies on), so the filesystem
of the rootfs is the only difference.
