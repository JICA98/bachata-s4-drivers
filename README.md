# bachata-s4-drivers

ARM64 **glibc** Mesa Turnip Vulkan packages for [BachataS4](https://github.com/JICA98).

This repository builds and hosts driver ZIPs. It does **not** ship binaries in git — only scripts and CI. Release assets are published to GitHub Releases.

Design: [`docs/superpowers/specs/2026-07-10-glibc-turnip-drivers-design.md`](docs/superpowers/specs/2026-07-10-glibc-turnip-drivers-design.md)

## Tracked lines

| Line id | Upstream branch | Source |
|---------|-----------------|--------|
| `gen8` | `turnip/gen8` | [mesa-unified](https://github.com/whitebelyash/mesa-unified/tree/turnip/gen8) |
| `mojo-26.1` | `mojo/26.1` | [mesa-unified](https://github.com/whitebelyash/mesa-unified/tree/mojo/26.1) |
| `mojo-25.0` | `mojo/25.0` | [mesa-unified](https://github.com/whitebelyash/mesa-unified/tree/mojo/25.0) |

## Package format

Each release asset is a flat ZIP:

- `libvulkan_freedreno.so` — AArch64 ELF, glibc-linked (`libc.so.6`)
- `freedreno_icd.aarch64.json` — Vulkan ICD
- `meta.json` — includes `"abi": "linux-aarch64-glibc"`

### Naming

```
Turnip-<line>-v<N>-<shortsha>-EMULATOR.zip
```

Examples:

- `Turnip-gen8-v3-7fdde2f-EMULATOR.zip`
- `Turnip-mojo-26.1-v2-08e7443-EMULATOR.zip`

Git tags: `<line>-v<N>` (for example `gen8-v3`).

Per-line counters (`v1`, `v2`, …) increase only when that line publishes a new package. The short SHA is the mesa-unified commit.

## Local build

### Dependencies (Ubuntu/Debian)

```bash
sudo dpkg --add-architecture arm64
sudo apt-get update
sudo apt-get install -y \
  git meson ninja-build python3-mako python3-setuptools \
  glslang-tools flex bison pkg-config unzip file binutils \
  gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
  libz-dev:arm64 libexpat1-dev:arm64 \
  libx11-dev:arm64 libxcb1-dev:arm64 libx11-xcb-dev:arm64 \
  libxcb-dri3-dev:arm64 libxcb-present-dev:arm64 \
  libxcb-xfixes0-dev:arm64 libxcb-randr0-dev:arm64 \
  libxcb-shm0-dev:arm64 libxcb-sync-dev:arm64 \
  libxshmfence-dev:arm64
```

### Build one line

```bash
# Force local v1 without querying GitHub releases
FORCE_VERSION=1 FORCE=1 ./scripts/build-driver.sh mojo-26.1
FORCE_VERSION=1 FORCE=1 ./scripts/build-driver.sh gen8
FORCE_VERSION=1 FORCE=1 ./scripts/build-driver.sh mojo-25.0
```

Outputs land in `dist/` (gitignored).

### Validate

```bash
./scripts/validate-driver.sh dist/Turnip-mojo-26.1-v1-*.zip
./tests/run-all.sh
```

## CI

Workflow: [`.github/workflows/daily-drivers.yml`](.github/workflows/daily-drivers.yml)

| Trigger | Behavior |
|---------|----------|
| Push to `psycho` | Build all lines; release only if the mesa tip is new (or force via dispatch) |
| Daily `06:00` UTC | Check each branch tip; build and release only if the commit is new |
| `workflow_dispatch` | Manual; choose `line` (`all` or one line) and optional `force` |

CI uses the same scripts as local builds, then creates a GitHub Release with the `-EMULATOR.zip` asset. No driver binaries are committed to the repository.

## Scripts

| Script | Role |
|--------|------|
| `scripts/build-driver.sh` | Clone tip, cross-build, package, validate |
| `scripts/package-driver.sh` | Write meta/ICD/zip |
| `scripts/validate-driver.sh` | Layout / ABI / ELF / glibc checks |
| `scripts/next-version.sh` | Next `vN` + already-released detection |
| `scripts/check-tip.sh` | Resolve remote tip SHA |

## License

Apache-2.0 (see `LICENSE`). Mesa itself is under MIT and other licenses from upstream.
