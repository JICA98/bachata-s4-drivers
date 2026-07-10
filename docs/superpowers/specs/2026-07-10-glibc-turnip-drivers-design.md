# Glibc Turnip Drivers Host (bachata-s4-drivers)

## Goal

Host and automatically publish **ARM64 glibc** Mesa Turnip Vulkan driver packages for BachataS4 from three tracked branches of `whitebelyash/mesa-unified`. Users (and later the Bachata app) download immutable GitHub Release assets. The repository never commits driver binaries.

## Constraints

- Work only in `bachata-s4-drivers`. **Do not modify** the Bachata-S4 emulator repository.
- Packages must be real **glibc** aarch64 drivers (`abi: linux-aarch64-glibc`), not Android NDK/bionic adrenotools packages.
- Bachata import layout is the contract: flat ZIP with `meta.json`, ICD JSON, and `libvulkan_freedreno.so`.
- Release assets must end in `-EMULATOR.zip` so Bachata’s existing release client filter can consume them after the trusted repo is pointed here.
- Local validation first: build all three lines, hand ZIPs to the maintainer for device testing, then use CI for production releases (no zip push to git).

## Upstream sources

| Line id | Git branch | Upstream |
|---------|------------|----------|
| `gen8` | `turnip/gen8` | https://github.com/whitebelyash/mesa-unified/tree/turnip/gen8 |
| `mojo-26.1` | `mojo/26.1` | https://github.com/whitebelyash/mesa-unified/tree/mojo/26.1 |
| `mojo-25.0` | `mojo/25.0` | https://github.com/whitebelyash/mesa-unified/tree/mojo/25.0 |

Source repository URL: `https://github.com/whitebelyash/mesa-unified`.

Daily automation tracks **branch tip commits**, not GitHub Releases on mesa-unified (that repo does not publish release artifacts).

## Architecture (recommended approach)

Native **glibc cross-compile** on Linux x86_64:

1. Shallow-clone the selected mesa-unified branch.
2. Meson/ninja cross-build Turnip (`freedreno`) for `aarch64-linux-gnu` with KGSL.
3. Package and validate a Bachata-compatible ZIP.
4. CI assigns the next per-line version and creates a GitHub Release.

Rejected alternatives:

- Forking StevenMXZ Android NDK pipelines (bionic output, wrong ABI for host-glibc Box64).
- Mirroring third-party prebuilt ZIPs without compiling (no control over glibc packaging).

## Package format

### ZIP layout (flat, no nested directories)

| File | Role |
|------|------|
| `libvulkan_freedreno.so` | AArch64 ELF shared object, glibc-linked |
| `freedreno_icd.aarch64.json` | Vulkan ICD (`library_path` = `libvulkan_freedreno.so`) |
| `meta.json` | Installer metadata |

### `meta.json` required and standard fields

```json
{
  "schemaVersion": 1,
  "name": "Turnip mojo-26.1 v2",
  "description": "glibc Turnip for Bachata S4 from whitebelyash/mesa-unified@mojo/26.1",
  "author": "bachata-s4-drivers",
  "packageVersion": "2",
  "vendor": "Mesa",
  "driverVersion": "Vulkan 1.4.353",
  "minApi": 31,
  "libraryName": "libvulkan_freedreno.so",
  "abi": "linux-aarch64-glibc",
  "sourceRepo": "https://github.com/whitebelyash/mesa-unified",
  "sourceBranch": "mojo/26.1",
  "sourceCommit": "2a6fe3d35a3b59a21418946af1c45d109422fbc7",
  "line": "mojo-26.1",
  "releaseVersion": 2
}
```

- `driverVersion` and `sourceCommit` are filled at package time from the built Mesa/ICD (example values above).
- `abi` must be exactly `linux-aarch64-glibc`.
- `libraryName` must match the `.so` filename in the ZIP.
- Extra fields are allowed for provenance.

### Golden reference

The maintainer’s existing `Turnip_Gen8_V32_glibc.zip` defines the expected three-file layout and glibc dynamic linkage. It is a packaging reference only; it is **not** re-published as a release seed. All seed and CI packages are rebuilt from branch tips.

## Versioning and naming

### Asset filename

```
Turnip-<line>-v<N>-<shortsha>-EMULATOR.zip
```

Examples:

- `Turnip-mojo-26.1-v2-09df2ee-EMULATOR.zip`
- `Turnip-gen8-v3-09df2ef-EMULATOR.zip`
- `Turnip-mojo-25.0-v4-abcdef1-EMULATOR.zip`

### Git tag and release title

| Field | Format | Example |
|-------|--------|---------|
| Tag | `<line>-v<N>` | `mojo-26.1-v2` |
| Title | `Turnip <line> v<N> (<shortsha>)` | `Turnip mojo-26.1 v2 (09df2ee)` |
| Short SHA | first 7 chars of commit | `09df2ee` |

### Counter rules

1. Counters are **independent per line** (`gen8` v3 and `mojo-26.1` v1 can coexist).
2. Next `vN` = maximum existing GitHub tag matching `<line>-v*` + 1; if none, `v1`.
3. Bump only when publishing a new package for that line.
4. If the tip commit SHA already has a successful release for that line, **skip** (no empty version bump). Detection: list that line’s release assets and match either the short SHA segment in `Turnip-<line>-v*-<shortsha>-EMULATOR.zip` or the full SHA recorded in the release body / `meta` provenance. Matching short SHA is sufficient for skip decisions.
5. Counters are **not** stored in git files; they are derived from tags/releases so local and CI stay consistent after the first publish.
6. Local testing may set `FORCE_VERSION=1` (or similar) without calling GitHub.

## Repository layout

```
bachata-s4-drivers/
  README.md
  LICENSE
  .gitignore                 # dist/, work/, *.so, *.zip, mesa clones
  lines.conf                 # line id → branch mapping
  scripts/
    build-driver.sh          # clone + meson build one line → package
    package-driver.sh        # write meta.json, ICD, create zip
    validate-driver.sh       # ELF/ABI/layout gates
    next-version.sh          # resolve next vN from GitHub tags
  meson/
    aarch64-linux-gnu.ini    # cross-file
  .github/workflows/
    daily-drivers.yml
  docs/superpowers/specs/
    2026-07-10-glibc-turnip-drivers-design.md
  dist/                      # local outputs only (gitignored)
  work/                      # clones and build trees (gitignored)
```

Binary artifacts (`dist/`, zips, `.so` files, mesa checkouts) are never committed.

## Build pipeline

### Tooling

| Item | Choice |
|------|--------|
| Host | Linux x86_64 |
| Cross compiler | `aarch64-linux-gnu-gcc` / `g++` |
| Build system | meson + ninja |
| Vulkan driver | `freedreno` (Turnip) |
| Kernel mode interface | `kgsl` |
| Target system | Linux glibc (not Android NDK / not bionic) |

### Local CLI

```bash
./scripts/build-driver.sh gen8
./scripts/build-driver.sh mojo-26.1
./scripts/build-driver.sh mojo-25.0

FORCE_VERSION=1 ./scripts/build-driver.sh mojo-26.1
```

Each success prints a path under `dist/Turnip-<line>-v<N>-<shortsha>-EMULATOR.zip`.

### Build steps (per line)

1. Map line id → branch via `lines.conf`.
2. Shallow-clone or update `work/mesa-unified-<line>` to the branch tip; record full SHA.
3. Configure meson with the aarch64-linux-gnu cross-file, release build, Turnip/KGSL, disable unneeded Gallium/EGL/GLES/LLVM where possible.
4. `ninja install` into a line-specific prefix; collect `libvulkan_freedreno.so`.
5. Run packaging (ICD + meta.json + zip).
6. Run validation; fail closed if any gate fails.

Exact meson flags may be tuned per branch during the first local build so the resulting `.so` needs `libc.so.6` and matches the golden layout.

### Validation gates

A package fails if any check fails:

1. ZIP contains exactly the three expected top-level files; no path traversal, no nested dirs required by the importer.
2. `meta.json` parses; `abi == linux-aarch64-glibc`; `libraryName` present.
3. Library is ELF 64-bit AArch64 shared object.
4. Dynamic section includes `libc.so.6` (glibc marker).
5. Reject packages that look like Android bionic-only linkage when that can be detected.

## GitHub Actions

### Workflow file

`.github/workflows/daily-drivers.yml`

### Triggers

| Trigger | Behavior |
|---------|----------|
| `schedule` | Daily (target: `0 6 * * *` UTC) |
| `workflow_dispatch` | Manual; inputs: `line` (`all` \| `gen8` \| `mojo-26.1` \| `mojo-25.0`), `force` (rebuild even if SHA already released) |

### Per-line job behavior

1. Checkout this repository (scripts only).
2. Install apt/toolchain deps (cross compiler, meson, ninja, glslang, python/mako, zlib and X11/xcb headers as required).
3. Resolve tip SHA for the line’s branch via GitHub API.
4. List existing tags/releases for prefix `<line>-v`.
5. If tip SHA already released for that line and `force` is false → skip.
6. Else compute next `vN`, build, validate, create tag `<line>-vN` and a GitHub Release with the single `-EMULATOR.zip` asset.
7. Release body includes line, branch, full SHA, optional compare URL to previous tip, and validation summary.

### Parallelism

Use a **matrix** of the three lines so:

- Builds run independently when multiple tips moved.
- One failing branch does not block the others.
- Each job only creates tags under its own line prefix (no counter collision).

### Permissions

```yaml
permissions:
  contents: write
```

Default `GITHUB_TOKEN` is sufficient unless rate limits later require a PAT.

### Local/CI parity

The same shell scripts perform clone, build, package, and validate. CI adds tip comparison, version resolution from tags, and `gh release create`.

## Rollout plan

### Phase 1 — Local proof

1. Implement scripts, cross-file, `lines.conf`, `.gitignore`, README.
2. Build all three lines locally with validation.
3. Deliver ZIPs from `dist/` to the maintainer for Bachata import / device smoke tests.
4. **Do not** publish GitHub Releases until the maintainer confirms packages work.

### Phase 2 — CI production

1. Commit and push scripts and workflow only (no binaries).
2. Run `workflow_dispatch` for one line, then all three, producing first `v1` releases.
3. Enable the daily schedule.
4. Confirm asset names and download URLs on GitHub Releases.

### Phase 3 — Steady state

| Condition | Result |
|-----------|--------|
| Daily run, no tip change | All lines skipped; job green |
| One branch moves | Only that line builds and publishes `vN+1` |
| Build/validation fails | No tag/release for that line |
| Manual force | New `vN` even if SHA unchanged |

### Out of scope for this project

- Changing Bachata-S4 trusted repository URL or client code.
- Magisk/KSU or bionic adrenotools packages.
- Committing or force-pushing driver binaries into git history.

## Success criteria

- Local and CI produce ZIPs with the three-file glibc layout and correct `meta.json` ABI.
- Filenames follow `Turnip-<line>-v<N>-<shortsha>-EMULATOR.zip` so users see the latest revision per line at a glance.
- Git history remains scripts and docs only; binaries exist only as Release assets (and local `dist/`).
- Bachata-S4 tree is never modified by this work.
- Daily automation only spends build minutes when a tracked branch tip is new (or force is requested).

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| A mesa-unified branch fails to cross-compile | Per-line matrix isolation; tune meson flags per branch |
| Missing cross-compile libraries on the runner | Pin apt packages in the workflow; document local deps in README |
| Duplicate version tags | One job per line; tag creation fails closed on conflict |
| High GitHub Actions minutes | Build only on SHA change; optional ccache |
| Package works on build host checks but fails in Bachata | Phase 1 device testing before first CI release |

## Implementation sequence (after plan approval)

1. Scaffold repo files (gitignore, lines.conf, cross-file, script stubs, README).
2. Implement package + validate against golden layout.
3. Implement glibc meson build; iterate until all three lines produce valid ZIPs locally.
4. Hand ZIPs to maintainer for testing.
5. Implement `next-version.sh` and daily workflow.
6. After maintainer OK, push scripts and run first CI releases.
