# bachata-s4-drivers

ARM64 **glibc** Mesa Turnip packages for BachataS4.

See `docs/superpowers/specs/2026-07-10-glibc-turnip-drivers-design.md`.

## Quick start (after scripts land)

```bash
./scripts/build-driver.sh mojo-26.1
./tests/run-all.sh
```

Binaries land in `dist/` (gitignored). Releases are published only by CI.
