# bachata-s4-drivers

ARM64 **glibc** Mesa Turnip packages for BachataS4.

See `docs/superpowers/specs/2026-07-10-glibc-turnip-drivers-design.md`.

## Quick start

```bash
FORCE_VERSION=1 FORCE=1 ./scripts/build-driver.sh mojo-26.1
./tests/run-all.sh
```

Binaries land in `dist/` (gitignored). Releases are published only by CI.

## Host dependencies (Ubuntu/Debian)

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
