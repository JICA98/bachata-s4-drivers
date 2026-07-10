# Glibc Turnip Drivers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and validate ARM64 glibc Turnip driver ZIPs for three `mesa-unified` branches locally, then automate daily GitHub Releases with per-line `vN` versioning — without committing binaries.

**Architecture:** Shell scripts cross-compile Mesa Turnip (`freedreno` + `kgsl`) for `aarch64-linux-gnu`, package Bachata-compatible flat ZIPs (`meta.json` + ICD + `.so`), validate ELF/ABI, and a GitHub Actions matrix publishes only when a branch tip is new.

**Tech Stack:** bash, meson, ninja, `aarch64-linux-gnu-gcc`, Python 3 (mako for Mesa), GitHub Actions, `gh` CLI, GitHub Releases API.

## Global Constraints

- Work only in `/home/jica/repo/bachata-s4-drivers`. Never modify `/home/jica/repo/Bachata-S4`.
- `abi` in every package must be exactly `linux-aarch64-glibc`.
- Asset names must match `Turnip-<line>-v<N>-<shortsha>-EMULATOR.zip`.
- Tags must match `<line>-v<N>` (examples: `gen8-v1`, `mojo-26.1-v2`).
- Tracked lines: `gen8` → `turnip/gen8`, `mojo-26.1` → `mojo/26.1`, `mojo-25.0` → `mojo/25.0` on `https://github.com/whitebelyash/mesa-unified`.
- Never commit `dist/`, `work/`, `*.zip`, `*.so`, or mesa clones.
- Spec: `docs/superpowers/specs/2026-07-10-glibc-turnip-drivers-design.md`.
- Golden layout reference (local, untracked): `Turnip_Gen8_V32_glibc.zip` — three files: `libvulkan_freedreno.so`, `freedreno_icd.aarch64.json`, `meta.json`.

## File map

| Path | Responsibility |
|------|----------------|
| `.gitignore` | Ignore build outputs and binaries |
| `lines.conf` | Map line id → git branch |
| `meson/aarch64-linux-gnu.ini` | Meson cross-file for glibc aarch64 |
| `scripts/lib.sh` | Shared helpers (repo root, logging, require tools) |
| `scripts/package-driver.sh` | Write ICD + meta.json + zip into `dist/` |
| `scripts/validate-driver.sh` | Layout / meta / ELF / glibc gates; exit non-zero on failure |
| `scripts/next-version.sh` | Compute next `vN` and detect SHA already released |
| `scripts/build-driver.sh` | Clone mesa branch, meson build, package, validate |
| `scripts/check-tip.sh` | Resolve remote tip SHA for a line |
| `tests/fixtures/` | Tiny fake package dirs/zips for validate tests |
| `tests/test-validate-driver.sh` | Shell tests for validate-driver |
| `tests/test-package-driver.sh` | Shell tests for package naming + meta |
| `tests/test-next-version.sh` | Shell tests for version bump logic |
| `tests/run-all.sh` | Run all shell tests |
| `.github/workflows/daily-drivers.yml` | Daily + manual matrix build/release |
| `README.md` | Local build, deps, naming, CI notes |

---

### Task 1: Repo scaffold and ignore rules

**Files:**
- Create: `.gitignore`
- Create: `lines.conf`
- Create: `README.md` (minimal stub; expand in Task 7)
- Create: `scripts/lib.sh`
- Create: `tests/run-all.sh`

**Interfaces:**
- Consumes: none
- Produces: `lines.conf` keys `gen8`, `mojo-26.1`, `mojo-25.0`; `scripts/lib.sh` functions `repo_root`, `log`, `die`, `require_cmd`

- [ ] **Step 1: Write `.gitignore`**

```gitignore
/dist/
/work/
*.so
*.zip
*.o
*.a
.cache/
__pycache__/
*.pyc
.meson*
```

Note: deliberately ignore `*.zip` so the local golden `Turnip_Gen8_V32_glibc.zip` and all `dist/` outputs stay untracked.

- [ ] **Step 2: Write `lines.conf`**

```conf
# line_id=git_branch
gen8=turnip/gen8
mojo-26.1=mojo/26.1
mojo-25.0=mojo/25.0
```

- [ ] **Step 3: Write `scripts/lib.sh`**

```bash
#!/usr/bin/env bash
# Shared helpers for bachata-s4-drivers scripts.
set -euo pipefail

repo_root() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)"
  printf '%s\n' "$here"
}

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "missing required command: $c"
  done
}

line_branch() {
  # Usage: line_branch <line_id>
  # Prints branch name from lines.conf or dies.
  local line_id="$1"
  local conf root branch
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  conf="$root/lines.conf"
  [[ -f "$conf" ]] || die "lines.conf not found at $conf"
  branch="$(awk -F= -v id="$line_id" '$1==id {print $2; found=1} END{exit !found}' "$conf")" \
    || die "unknown line id: $line_id (not in lines.conf)"
  printf '%s\n' "$branch"
}

MESA_REPO_URL="${MESA_REPO_URL:-https://github.com/whitebelyash/mesa-unified}"
```

- [ ] **Step 4: Write minimal `README.md`**

```markdown
# bachata-s4-drivers

ARM64 **glibc** Mesa Turnip packages for BachataS4.

See `docs/superpowers/specs/2026-07-10-glibc-turnip-drivers-design.md`.

## Quick start (after scripts land)

```bash
./scripts/build-driver.sh mojo-26.1
./tests/run-all.sh
```

Binaries land in `dist/` (gitignored). Releases are published only by CI.
```

- [ ] **Step 5: Write `tests/run-all.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
for t in "$root"/tests/test-*.sh; do
  [[ -f "$t" ]] || continue
  echo "RUN $t"
  if bash "$t"; then
    echo "PASS $t"
  else
    echo "FAIL $t"
    fail=1
  fi
done
exit "$fail"
```

- [ ] **Step 6: Make scripts executable and commit**

```bash
chmod +x scripts/lib.sh tests/run-all.sh
git add .gitignore lines.conf scripts/lib.sh README.md tests/run-all.sh
git commit -m "chore: scaffold driver repo layout and line map"
```

---

### Task 2: Package and validate scripts (TDD)

**Files:**
- Create: `scripts/package-driver.sh`
- Create: `scripts/validate-driver.sh`
- Create: `tests/fixtures/fake-libvulkan_freedreno.so` (generated in test via `printf` + note: use a real tiny aarch64 ELF or mock mode)
- Create: `tests/test-package-driver.sh`
- Create: `tests/test-validate-driver.sh`

**Interfaces:**
- Consumes: `scripts/lib.sh`
- Produces:
  - `package-driver.sh` CLI:
    ```
    package-driver.sh \
      --line <line_id> \
      --version <N> \
      --commit <full_sha> \
      --branch <branch> \
      --library <path/to/libvulkan_freedreno.so> \
      --driver-version "Vulkan 1.4.xxx" \
      --outdir <dist_dir>
    ```
    Exit 0; prints absolute zip path on stdout last line.
  - `validate-driver.sh` CLI: `validate-driver.sh <path/to.zip>` → exit 0 ok / 1 fail; messages on stderr.

- [ ] **Step 1: Write failing validate tests**

Create `tests/test-validate-driver.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
validate="$root/scripts/validate-driver.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Expect script to exist (will fail until implemented)
[[ -x "$validate" ]] || { echo "validate-driver.sh missing"; exit 1; }

# Build a minimal valid-looking package from golden zip if present, else synthetic meta+icd + copy golden .so
golden="$root/Turnip_Gen8_V32_glibc.zip"
if [[ -f "$golden" ]]; then
  cp "$golden" "$tmpdir/good.zip"
  "$validate" "$tmpdir/good.zip"
else
  echo "SKIP full golden test (no Turnip_Gen8_V32_glibc.zip)"
fi

# Bad: missing meta
mkdir -p "$tmpdir/bad1"
printf 'x' >"$tmpdir/bad1/libvulkan_freedreno.so"
printf '{}' >"$tmpdir/bad1/freedreno_icd.aarch64.json"
( cd "$tmpdir/bad1" && zip -q "$tmpdir/bad-missing-meta.zip" libvulkan_freedreno.so freedreno_icd.aarch64.json )
if "$validate" "$tmpdir/bad-missing-meta.zip"; then
  echo "expected validate to fail for missing meta"; exit 1
fi

# Bad: wrong abi
mkdir -p "$tmpdir/bad2"
if [[ -f "$golden" ]]; then
  unzip -q -o "$golden" -d "$tmpdir/bad2"
  # rewrite abi
  python3 - <<'PY' "$tmpdir/bad2/meta.json"
import json,sys
p=sys.argv[1]
m=json.load(open(p))
m["abi"]="android-aarch64-bionic"
json.dump(m, open(p,"w"))
PY
  ( cd "$tmpdir/bad2" && zip -q "$tmpdir/bad-abi.zip" libvulkan_freedreno.so freedreno_icd.aarch64.json meta.json )
  if "$validate" "$tmpdir/bad-abi.zip"; then
    echo "expected validate to fail for wrong abi"; exit 1
  fi
fi

echo "validate tests ok"
```

- [ ] **Step 2: Run tests — expect fail (script missing)**

```bash
bash tests/test-validate-driver.sh
```

Expected: fail with `validate-driver.sh missing` or not executable.

- [ ] **Step 3: Implement `scripts/validate-driver.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

zip_path="${1:-}"
[[ -n "$zip_path" && -f "$zip_path" ]] || die "usage: validate-driver.sh <zip>"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
unzip -q -o "$zip_path" -d "$tmpdir"

# Exactly three expected entries at top level (zip may list with or without ./)
mapfile -t entries < <(unzip -Z1 "$zip_path" | sed 's|^\./||' | sort)
expected=$'freedreno_icd.aarch64.json\nlibvulkan_freedreno.so\nmeta.json'
actual="$(printf '%s\n' "${entries[@]}" | sort)"
[[ "$actual" == "$expected" ]] || die "zip entries mismatch: got: ${entries[*]}"

# Reject path traversal / nested paths
while IFS= read -r e; do
  [[ "$e" != */* && "$e" != *..* ]] || die "illegal zip entry path: $e"
done <<<"$(printf '%s\n' "${entries[@]}")"

meta="$tmpdir/meta.json"
lib="$tmpdir/libvulkan_freedreno.so"
icd="$tmpdir/freedreno_icd.aarch64.json"
[[ -f "$meta" && -f "$lib" && -f "$icd" ]] || die "missing required files after extract"

python3 - "$meta" <<'PY'
import json,sys
m=json.load(open(sys.argv[1]))
for k in ("schemaVersion","name","libraryName","abi"):
    if k not in m: raise SystemExit(f"meta missing {k}")
if m.get("abi") != "linux-aarch64-glibc":
    raise SystemExit(f"bad abi: {m.get('abi')}")
if m.get("libraryName") != "libvulkan_freedreno.so":
    raise SystemExit(f"bad libraryName: {m.get('libraryName')}")
if int(m.get("schemaVersion",0)) < 1:
    raise SystemExit("schemaVersion must be >= 1")
print("meta ok")
PY

file_out="$(file -b "$lib")"
[[ "$file_out" == *"ELF"* && "$file_out" == *"aarch64"* ]] || die "library is not ELF aarch64: $file_out"
[[ "$file_out" == *"shared object"* || "$file_out" == *"LSB shared object"* ]] || die "library is not a shared object: $file_out"

# glibc markers
dyn="$(readelf -d "$lib" 2>/dev/null || true)"
printf '%s\n' "$dyn" | grep -q 'libc.so.6' || die "library does not link libc.so.6 (not glibc?)"
# Hard reject common Android bionic-only soname if present without glibc (already require libc.so.6)

log "validate OK: $zip_path"
```

- [ ] **Step 4: Implement `scripts/package-driver.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

line=""; version=""; commit=""; branch=""; library=""; driver_version="Vulkan 1.4.0"; outdir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --line) line="$2"; shift 2 ;;
    --version) version="$2"; shift 2 ;;
    --commit) commit="$2"; shift 2 ;;
    --branch) branch="$2"; shift 2 ;;
    --library) library="$2"; shift 2 ;;
    --driver-version) driver_version="$2"; shift 2 ;;
    --outdir) outdir="$2"; shift 2 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[[ -n "$line" && -n "$version" && -n "$commit" && -n "$branch" && -n "$library" && -n "$outdir" ]] \
  || die "usage: package-driver.sh --line --version --commit --branch --library --outdir [--driver-version]"
[[ -f "$library" ]] || die "library not found: $library"

shortsha="${commit:0:7}"
asset="Turnip-${line}-v${version}-${shortsha}-EMULATOR.zip"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

cp "$library" "$stage/libvulkan_freedreno.so"

# ICD api_version: best-effort parse from driver_version (e.g. "Vulkan 1.4.353" -> 1.4.353)
api_ver="$(printf '%s' "$driver_version" | sed -E 's/.*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
[[ "$api_ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || api_ver="1.4.0"

cat >"$stage/freedreno_icd.aarch64.json" <<EOF
{
  "file_format_version": "1.0.1",
  "ICD": {
    "library_path": "libvulkan_freedreno.so",
    "library_arch": "64",
    "api_version": "${api_ver}"
  }
}
EOF

python3 - "$stage/meta.json" <<PY
import json
meta = {
  "schemaVersion": 1,
  "name": f"Turnip ${line} v${version}",
  "description": f"glibc Turnip for Bachata S4 from whitebelyash/mesa-unified@${branch}",
  "author": "bachata-s4-drivers",
  "packageVersion": str(${version}),
  "vendor": "Mesa",
  "driverVersion": """${driver_version}""",
  "minApi": 31,
  "libraryName": "libvulkan_freedreno.so",
  "abi": "linux-aarch64-glibc",
  "sourceRepo": "https://github.com/whitebelyash/mesa-unified",
  "sourceBranch": """${branch}""",
  "sourceCommit": """${commit}""",
  "line": """${line}""",
  "releaseVersion": int(${version}),
}
json.dump(meta, open("""$stage/meta.json""", "w"), indent=2)
print("wrote meta")
PY

mkdir -p "$outdir"
out_abs="$(cd "$outdir" && pwd)/$asset"
rm -f "$out_abs"
( cd "$stage" && zip -9 -q "$out_abs" libvulkan_freedreno.so freedreno_icd.aarch64.json meta.json )
printf '%s\n' "$out_abs"
```

Fix the python heredoc carefully when implementing: prefer passing values via env vars to avoid quoting bugs:

```bash
export PKG_LINE="$line" PKG_VERSION="$version" PKG_BRANCH="$branch" \
  PKG_COMMIT="$commit" PKG_DRIVER_VERSION="$driver_version"
python3 - <<'PY'
import json, os
meta = {
  "schemaVersion": 1,
  "name": f"Turnip {os.environ['PKG_LINE']} v{os.environ['PKG_VERSION']}",
  "description": f"glibc Turnip for Bachata S4 from whitebelyash/mesa-unified@{os.environ['PKG_BRANCH']}",
  "author": "bachata-s4-drivers",
  "packageVersion": str(os.environ["PKG_VERSION"]),
  "vendor": "Mesa",
  "driverVersion": os.environ["PKG_DRIVER_VERSION"],
  "minApi": 31,
  "libraryName": "libvulkan_freedreno.so",
  "abi": "linux-aarch64-glibc",
  "sourceRepo": "https://github.com/whitebelyash/mesa-unified",
  "sourceBranch": os.environ["PKG_BRANCH"],
  "sourceCommit": os.environ["PKG_COMMIT"],
  "line": os.environ["PKG_LINE"],
  "releaseVersion": int(os.environ["PKG_VERSION"]),
}
json.dump(meta, open(os.environ["PKG_META_PATH"], "w"), indent=2)
PY
```

(Set `PKG_META_PATH` to the staging `meta.json` path before invoking Python.)

- [ ] **Step 5: Write `tests/test-package-driver.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
pkg="$root/scripts/package-driver.sh"
val="$root/scripts/validate-driver.sh"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

[[ -x "$pkg" ]] || { echo "package-driver.sh missing"; exit 1; }

# Prefer real .so from golden zip
lib=""
if [[ -f "$root/Turnip_Gen8_V32_glibc.zip" ]]; then
  unzip -q -o "$root/Turnip_Gen8_V32_glibc.zip" libvulkan_freedreno.so -d "$tmpdir"
  lib="$tmpdir/libvulkan_freedreno.so"
else
  echo "SKIP package test without golden zip"; exit 0
fi

out="$("$pkg" \
  --line gen8 \
  --version 1 \
  --commit 09df2ee2ba97f76d4da244bc98e843f807bfa99f \
  --branch turnip/gen8 \
  --library "$lib" \
  --driver-version "Vulkan 1.4.353" \
  --outdir "$tmpdir/dist")"

base="$(basename "$out")"
[[ "$base" == "Turnip-gen8-v1-09df2ee-EMULATOR.zip" ]] || { echo "bad name: $base"; exit 1; }
"$val" "$out"
echo "package tests ok"
```

- [ ] **Step 6: Run all package/validate tests**

```bash
chmod +x scripts/package-driver.sh scripts/validate-driver.sh tests/test-*.sh
bash tests/test-validate-driver.sh
bash tests/test-package-driver.sh
bash tests/run-all.sh
```

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/package-driver.sh scripts/validate-driver.sh tests/
git commit -m "feat: package and validate Bachata glibc Turnip ZIPs"
```

---

### Task 3: Version resolution (`next-version.sh`)

**Files:**
- Create: `scripts/next-version.sh`
- Create: `scripts/check-tip.sh`
- Create: `tests/test-next-version.sh`

**Interfaces:**
- Consumes: GitHub API optional (`GITHUB_REPOSITORY`, `GH_TOKEN`/`GITHUB_TOKEN`), or env overrides
- Produces:
  - `next-version.sh --line <id> [--sha <full_or_short>] [--repo owner/name]`
    - stdout: single integer N for next version
    - if `--sha` provided and already released for that line: exit code **2** and message `already_released` on stderr (unless `FORCE=1`)
  - `check-tip.sh --line <id>` → stdout full SHA of remote branch tip

- [ ] **Step 1: Write failing tests for next-version offline mode**

`tests/test-next-version.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
nv="$root/scripts/next-version.sh"
[[ -x "$nv" ]] || { echo "missing next-version"; exit 1; }

# Offline: mock tag list via TAGS_FILE
tags="$root/tests/fixtures/tags-sample.txt"
mkdir -p "$root/tests/fixtures"
cat >"$tags" <<'EOF'
gen8-v1
gen8-v3
mojo-26.1-v1
mojo-26.1-v2
mojo-25.0-v1
unrelated-v9
EOF

export TAGS_FILE="$tags"
n="$(FORCE=1 "$nv" --line gen8)"
[[ "$n" == "4" ]] || { echo "expected gen8 next 4 got $n"; exit 1; }

n="$(FORCE=1 "$nv" --line mojo-26.1)"
[[ "$n" == "3" ]] || { echo "expected mojo-26.1 next 3 got $n"; exit 1; }

n="$(FORCE=1 "$nv" --line mojo-25.0)"
[[ "$n" == "2" ]] || { echo "expected mojo-25.0 next 2 got $n"; exit 1; }

# Empty tags → 1
export TAGS_FILE="$root/tests/fixtures/tags-empty.txt"
: >"$TAGS_FILE"
n="$(FORCE=1 "$nv" --line gen8)"
[[ "$n" == "1" ]] || { echo "expected 1 got $n"; exit 1; }

# already_released via ASSETS_FILE
export TAGS_FILE="$tags"
export ASSETS_FILE="$root/tests/fixtures/assets-sample.txt"
cat >"$ASSETS_FILE" <<'EOF'
Turnip-gen8-v3-09df2ee-EMULATOR.zip
Turnip-mojo-26.1-v2-abcdef1-EMULATOR.zip
EOF
set +e
FORCE=0 "$nv" --line gen8 --sha 09df2ee2ba97f76d4da244bc98e843f807bfa99f
code=$?
set -e
[[ "$code" == "2" ]] || { echo "expected exit 2 for already_released"; exit 1; }

echo "next-version tests ok"
```

- [ ] **Step 2: Run test — expect fail**

```bash
bash tests/test-next-version.sh
```

Expected: missing next-version.

- [ ] **Step 3: Implement `scripts/next-version.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

line=""; sha=""; repo="${GITHUB_REPOSITORY:-JICA98/bachata-s4-drivers}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --line) line="$2"; shift 2 ;;
    --sha) sha="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    *) die "unknown arg: $1" ;;
  esac
done
[[ -n "$line" ]] || die "usage: next-version.sh --line <id> [--sha <sha>] [--repo owner/name]"

short=""
if [[ -n "$sha" ]]; then
  short="${sha:0:7}"
fi

list_tags() {
  if [[ -n "${TAGS_FILE:-}" ]]; then
    cat "$TAGS_FILE"
    return
  fi
  # Prefer gh
  if command -v gh >/dev/null 2>&1; then
    gh api "repos/${repo}/tags?per_page=100" --jq '.[].name' 2>/dev/null || true
    return
  fi
  git ls-remote --tags "https://github.com/${repo}.git" 2>/dev/null \
    | awk '{print $2}' | sed 's|refs/tags/||' || true
}

list_assets() {
  if [[ -n "${ASSETS_FILE:-}" ]]; then
    cat "$ASSETS_FILE"
    return
  fi
  if command -v gh >/dev/null 2>&1; then
    gh release list --repo "$repo" --limit 100 2>/dev/null | awk '{print $1}' >/dev/null
    # List assets by fetching releases JSON
    gh api "repos/${repo}/releases?per_page=100" --jq '.[].assets[].name' 2>/dev/null || true
    return
  fi
  # No network fallback: empty
  true
}

if [[ -n "$short" && "${FORCE:-0}" != "1" ]]; then
  if list_assets | grep -E "^Turnip-${line}-v[0-9]+-${short}-EMULATOR\\.zip$" >/dev/null; then
    echo "already_released" >&2
    exit 2
  fi
fi

max=0
while IFS= read -r tag; do
  [[ -n "$tag" ]] || continue
  if [[ "$tag" =~ ^${line}-v([0-9]+)$ ]]; then
    n="${BASH_REMATCH[1]}"
    (( n > max )) && max=$n
  fi
done < <(list_tags)

echo $((max + 1))
```

Note: for `line` containing dots (`mojo-26.1`), bash regex needs the line escaped or use prefix strip:

```bash
prefix="${line}-v"
case "$tag" in
  "${prefix}"*)
    n="${tag#"$prefix"}"
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    ...
esac
```

Use the `case` form in the real implementation (safer with dots).

- [ ] **Step 4: Implement `scripts/check-tip.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

line=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --line) line="$2"; shift 2 ;;
    *) die "unknown arg: $1" ;;
  esac
done
[[ -n "$line" ]] || die "usage: check-tip.sh --line <id>"
branch="$(line_branch "$line")"

if [[ -n "${TIP_SHA_OVERRIDE:-}" ]]; then
  printf '%s\n' "$TIP_SHA_OVERRIDE"
  exit 0
fi

# Resolve via git ls-remote
sha="$(git ls-remote --heads "$MESA_REPO_URL" "$branch" | awk '{print $1; exit}')"
[[ -n "$sha" && ${#sha} -eq 40 ]] || die "failed to resolve tip for $branch"
printf '%s\n' "$sha"
```

- [ ] **Step 5: Run tests**

```bash
chmod +x scripts/next-version.sh scripts/check-tip.sh
bash tests/test-next-version.sh
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/next-version.sh scripts/check-tip.sh tests/
git commit -m "feat: resolve per-line vN and detect already-released SHAs"
```

---

### Task 4: Glibc cross-build (`build-driver.sh`)

**Files:**
- Create: `meson/aarch64-linux-gnu.ini`
- Create: `scripts/build-driver.sh`

**Interfaces:**
- Consumes: `line_branch`, `package-driver.sh`, `validate-driver.sh`, `next-version.sh`, `check-tip.sh`
- Produces: `build-driver.sh <line_id>` → builds into `work/`, packages into `dist/`, prints zip path
- Env:
  - `FORCE_VERSION` — skip GitHub version probe; use this integer
  - `FORCE=1` — ignore already_released when resolving version
  - `MESA_REPO_URL` — override source remote
  - `SKIP_VALIDATE=1` — only for emergency debug (default validate always)

- [ ] **Step 1: Write meson cross-file `meson/aarch64-linux-gnu.ini`**

```ini
[binaries]
c = 'aarch64-linux-gnu-gcc'
cpp = 'aarch64-linux-gnu-g++'
ar = 'aarch64-linux-gnu-ar'
strip = 'aarch64-linux-gnu-strip'
pkg-config = 'aarch64-linux-gnu-pkg-config'

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[properties]
needs_exe_wrapper = true
```

If `aarch64-linux-gnu-pkg-config` is missing on the host, install `pkg-config-aarch64-linux-gnu` or set:

```ini
pkg-config = ['env', 'PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig', 'pkg-config']
```

Prefer the env-wrapper form if the dedicated binary is absent on the build machine.

- [ ] **Step 2: Document host packages in README (append)**

```markdown
## Host dependencies (Ubuntu/Debian)

```bash
sudo apt-get update
sudo apt-get install -y \
  git meson ninja-build python3-mako python3-setuptools \
  glslang-tools flex bison pkg-config zip unzip file binutils \
  gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
  libz-dev:arm64 libexpat1-dev:arm64 \
  libx11-dev:arm64 libxcb1-dev:arm64 libx11-xcb-dev:arm64 \
  libxcb-dri3-dev:arm64 libxcb-present-dev:arm64 \
  libxcb-xfixes0-dev:arm64 libxcb-randr0-dev:arm64 \
  libxcb-shm0-dev:arm64 libxcb-sync-dev:arm64 \
  libxshmfence-dev:arm64 libwayland-dev:arm64
```

Enable arm64 multiarch if needed:

```bash
sudo dpkg --add-architecture arm64
sudo apt-get update
```
```

Tune the exact package list during the first real configure if meson reports missing deps.

- [ ] **Step 3: Implement `scripts/build-driver.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

line="${1:-}"
[[ -n "$line" ]] || die "usage: build-driver.sh <line_id>"
branch="$(line_branch "$line")"
root="$(cd "$(dirname "$0")/.." && pwd)"

require_cmd git meson ninja aarch64-linux-gnu-gcc aarch64-linux-gnu-g++ python3 zip unzip file readelf

work="$root/work/$line"
src="$work/mesa"
build="$work/build"
prefix="$work/prefix"
dist="$root/dist"
cross="$root/meson/aarch64-linux-gnu.ini"
mkdir -p "$work" "$dist"

log "line=$line branch=$branch"

# Fetch source
if [[ ! -d "$src/.git" ]]; then
  git clone --depth=1 --branch "$branch" "$MESA_REPO_URL" "$src"
else
  git -C "$src" fetch --depth=1 origin "$branch"
  git -C "$src" checkout -f "FETCH_HEAD"
fi
commit="$(git -C "$src" rev-parse HEAD)"
short="${commit:0:7}"
log "commit=$commit"

# Version
if [[ -n "${FORCE_VERSION:-}" ]]; then
  version="$FORCE_VERSION"
else
  set +e
  version="$(FORCE="${FORCE:-0}" "$root/scripts/next-version.sh" --line "$line" --sha "$commit")"
  code=$?
  set -e
  if [[ "$code" -eq 2 ]]; then
    log "already released for $line @$short — nothing to do"
    exit 0
  fi
  [[ "$code" -eq 0 ]] || die "next-version failed (exit $code)"
fi
log "version=v$version"

# Configure + build
rm -rf "$build" "$prefix"
mkdir -p "$prefix"

# Meson options: Turnip only, kgsl, release. Adjust if a branch rejects an option.
meson_args=(
  setup "$build" "$src"
  --cross-file "$cross"
  --prefix "$prefix"
  --libdir lib
  --buildtype release
  -Dplatforms=x11
  -Dgallium-drivers=
  -Dvulkan-drivers=freedreno
  -Dfreedreno-kmds=kgsl
  -Degl=disabled
  -Dgles1=disabled
  -Dgles2=disabled
  -Dopengl=false
  -Dllvm=disabled
  -Dshared-llvm=disabled
  -Dbuild-tests=false
  -Dxmlconfig=disabled
  -Dzlib=enabled
)

# Some branches may need -Dplatforms=linux or empty; try primary first.
if ! meson "${meson_args[@]}"; then
  log "primary meson setup failed; retry with platforms=[]"
  meson setup "$build" "$src" \
    --cross-file "$cross" \
    --prefix "$prefix" \
    --libdir lib \
    --buildtype release \
    -Dplatforms= \
    -Dgallium-drivers= \
    -Dvulkan-drivers=freedreno \
    -Dfreedreno-kmds=kgsl \
    -Degl=disabled \
    -Dllvm=disabled \
    -Dbuild-tests=false
fi

ninja -C "$build" install

lib="$(find "$prefix" -name 'libvulkan_freedreno.so' -type f | head -n1)"
[[ -n "$lib" && -f "$lib" ]] || die "libvulkan_freedreno.so not found under $prefix"

# Driver version string from ICD json if meson installed one, else fallback
driver_version="Vulkan 1.4.0"
icd_src="$(find "$prefix" -name '*freedreno*.json' -type f | head -n1 || true)"
if [[ -n "${icd_src:-}" ]]; then
  api="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ICD"].get("api_version",""))' "$icd_src" || true)"
  [[ -n "$api" ]] && driver_version="Vulkan $api"
fi

zip_path="$("$root/scripts/package-driver.sh" \
  --line "$line" \
  --version "$version" \
  --commit "$commit" \
  --branch "$branch" \
  --library "$lib" \
  --driver-version "$driver_version" \
  --outdir "$dist")"

if [[ "${SKIP_VALIDATE:-0}" != "1" ]]; then
  "$root/scripts/validate-driver.sh" "$zip_path"
fi

log "built $zip_path"
printf '%s\n' "$zip_path"
```

- [ ] **Step 4: Install any missing host deps, then build `mojo-26.1` first**

```bash
chmod +x scripts/build-driver.sh
FORCE_VERSION=1 FORCE=1 ./scripts/build-driver.sh mojo-26.1
```

Expected: eventually prints  
`.../dist/Turnip-mojo-26.1-v1-<shortsha>-EMULATOR.zip`  
and validate OK.

If meson fails, fix cross-file / apt packages / meson options until success. Do not weaken validate gates.

- [ ] **Step 5: Build remaining lines**

```bash
FORCE_VERSION=1 FORCE=1 ./scripts/build-driver.sh gen8
FORCE_VERSION=1 FORCE=1 ./scripts/build-driver.sh mojo-25.0
ls -la dist/
./scripts/validate-driver.sh dist/Turnip-*-EMULATOR.zip  # or loop
```

For each zip:

```bash
for z in dist/Turnip-*-EMULATOR.zip; do ./scripts/validate-driver.sh "$z"; done
```

Expected: three ZIPs, all validate OK.

- [ ] **Step 6: Hand off paths to maintainer (do not release)**

Record absolute paths of the three ZIPs in the commit message body of the scripts commit only (not the binaries). Leave files in `dist/` for local copy/testing.

- [ ] **Step 7: Commit scripts only**

```bash
git add meson/aarch64-linux-gnu.ini scripts/build-driver.sh README.md
git status   # confirm no zip/so staged
git commit -m "feat: cross-build glibc Turnip drivers for three mesa-unified lines"
```

---

### Task 5: GitHub Actions daily workflow

**Files:**
- Create: `.github/workflows/daily-drivers.yml`

**Interfaces:**
- Consumes: all scripts from Tasks 1–4
- Produces: GitHub Releases with one asset each; tags `<line>-vN`

- [ ] **Step 1: Write workflow**

```yaml
name: daily-drivers

on:
  schedule:
    - cron: "0 6 * * *"
  workflow_dispatch:
    inputs:
      line:
        description: "Line to build"
        required: true
        default: all
        type: choice
        options:
          - all
          - gen8
          - mojo-26.1
          - mojo-25.0
      force:
        description: "Force rebuild even if SHA already released"
        required: false
        default: false
        type: boolean

permissions:
  contents: write

jobs:
  prepare:
    runs-on: ubuntu-latest
    outputs:
      lines: ${{ steps.set.outputs.lines }}
    steps:
      - id: set
        run: |
          if [ "${{ github.event_name }}" = "workflow_dispatch" ] && [ "${{ inputs.line }}" != "all" ]; then
            echo 'lines=["${{ inputs.line }}"]' >> "$GITHUB_OUTPUT"
          else
            echo 'lines=["gen8","mojo-26.1","mojo-25.0"]' >> "$GITHUB_OUTPUT"
          fi

  build:
    needs: prepare
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        line: ${{ fromJson(needs.prepare.outputs.lines) }}
    steps:
      - uses: actions/checkout@v4

      - name: Install dependencies
        run: |
          sudo dpkg --add-architecture arm64
          sudo apt-get update
          sudo apt-get install -y \
            git meson ninja-build python3-mako python3-setuptools \
            glslang-tools flex bison pkg-config zip unzip file binutils \
            gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
            libz-dev:arm64 libexpat1-dev:arm64 \
            libx11-dev:arm64 libxcb1-dev:arm64 libx11-xcb-dev:arm64 \
            libxcb-dri3-dev:arm64 libxcb-present-dev:arm64 \
            libxcb-xfixes0-dev:arm64 libxcb-randr0-dev:arm64 \
            libxcb-shm0-dev:arm64 libxcb-sync-dev:arm64 \
            libxshmfence-dev:arm64

      - name: Build driver if needed
        id: build
        env:
          FORCE: ${{ github.event_name == 'workflow_dispatch' && inputs.force && '1' || '0' }}
          GITHUB_REPOSITORY: ${{ github.repository }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          chmod +x scripts/*.sh
          # Capture zip path; build-driver exits 0 with no zip if already released
          out="$(./scripts/build-driver.sh "${{ matrix.line }}" | tee /tmp/build-log.txt | tail -n1)"
          if [[ -f "$out" && "$out" == *.zip ]]; then
            echo "zip=$out" >> "$GITHUB_OUTPUT"
            echo "built=true" >> "$GITHUB_OUTPUT"
            # Parse version and sha from filename Turnip-LINE-vN-SHA-EMULATOR.zip
            base="$(basename "$out")"
            echo "asset=$base" >> "$GITHUB_OUTPUT"
          else
            echo "built=false" >> "$GITHUB_OUTPUT"
            echo "No new build for ${{ matrix.line }}"
          fi

      - name: Publish release
        if: steps.build.outputs.built == 'true'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          zip="${{ steps.build.outputs.zip }}"
          asset="${{ steps.build.outputs.asset }}"
          line="${{ matrix.line }}"
          # Turnip-gen8-v3-09df2ee-EMULATOR.zip or Turnip-mojo-26.1-v2-deadbee-EMULATOR.zip
          # Strip prefix/suffix carefully:
          rest="${asset#Turnip-}"
          rest="${rest%-EMULATOR.zip}"
          # rest = <line>-vN-shortsha where line may contain dots and hyphens
          shortsha="${rest##*-}"
          without_sha="${rest%-"$shortsha"}"
          ver="${without_sha##*-v}"
          # tag = line-vN
          tag="${line}-v${ver}"
          commit="$(unzip -p "$zip" meta.json | python3 -c 'import json,sys; print(json.load(sys.stdin)["sourceCommit"])')"
          branch="$(unzip -p "$zip" meta.json | python3 -c 'import json,sys; print(json.load(sys.stdin)["sourceBranch"])')"
          title="Turnip ${line} v${ver} (${shortsha})"
          body="$(cat <<EOF
          ## Turnip ${line} v${ver}

          - Branch: \`${branch}\`
          - Commit: \`${commit}\`
          - Asset: \`${asset}\`
          - ABI: \`linux-aarch64-glibc\`

          Built automatically for BachataS4 host-glibc runtime.
          EOF
          )"
          gh release create "$tag" "$zip" \
            --title "$title" \
            --notes "$body"
```

- [ ] **Step 2: Expand README with CI section**

Document:

- Daily schedule 06:00 UTC  
- Manual `workflow_dispatch` with `line` + `force`  
- Releases only; no binary commits  
- After local ZIPs verified, push and run workflow for first `v1`s  

- [ ] **Step 3: Commit workflow**

```bash
git add .github/workflows/daily-drivers.yml README.md
git commit -m "ci: daily glibc Turnip builds and GitHub Releases"
```

- [ ] **Step 4: Do not auto-publish until maintainer OK**

After push (maintainer action), first production releases use Actions UI → Run workflow → `line=all`, `force=false`.

---

### Task 6: Local three-line proof + maintainer handoff

**Files:**
- None required in git (uses `dist/`)

- [ ] **Step 1: Re-run unit tests**

```bash
./tests/run-all.sh
```

Expected: all PASS.

- [ ] **Step 2: Clean rebuild all three with FORCE_VERSION**

```bash
rm -rf work dist
mkdir -p dist
FORCE_VERSION=1 FORCE=1 ./scripts/build-driver.sh mojo-26.1
FORCE_VERSION=1 FORCE=1 ./scripts/build-driver.sh gen8
FORCE_VERSION=1 FORCE=1 ./scripts/build-driver.sh mojo-25.0
```

- [ ] **Step 3: Validate all**

```bash
for z in dist/Turnip-*-EMULATOR.zip; do
  echo "=== $z ==="
  ./scripts/validate-driver.sh "$z"
  unzip -l "$z"
  unzip -p "$z" meta.json
done
ls -lh dist/
```

Expected: three zips, three files each, `abi: linux-aarch64-glibc`.

- [ ] **Step 4: Report absolute paths to maintainer**

Print:

```text
dist/Turnip-gen8-v1-.......-EMULATOR.zip
dist/Turnip-mojo-26.1-v1-.......-EMULATOR.zip
dist/Turnip-mojo-25.0-v1-.......-EMULATOR.zip
```

Maintainer imports each into BachataS4 custom driver flow and smoke-tests.

- [ ] **Step 5: Stop for device confirmation**

Do **not** create GitHub Releases from the laptop. Wait for maintainer confirmation before Phase 2 (push + Actions).

---

### Task 7: Polish README and final checklist

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Write complete README** covering lines table, naming scheme, local build, deps, tests, CI, and “no binaries in git”.

- [ ] **Step 2: Final git status hygiene**

```bash
git status
# must not list staged zip/so; dist/ and work/ ignored
./tests/run-all.sh
```

- [ ] **Step 3: Commit README polish**

```bash
git add README.md
git commit -m "docs: document glibc Turnip build and release process"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Three mesa-unified branches | Task 1 `lines.conf`, Task 4 build |
| Glibc aarch64 package layout | Task 2 package/validate |
| `Turnip-<line>-vN-<sha>-EMULATOR.zip` | Task 2 package, Task 3 version |
| Tags `<line>-vN` | Task 5 release step |
| Local build all three before release | Task 4, Task 6 |
| No zip commits; CI publishes | Tasks 1, 5, 6 |
| Daily + workflow_dispatch | Task 5 |
| Skip if SHA already released | Task 3, Task 4, Task 5 |
| Per-line matrix isolation | Task 5 |
| Bachata-S4 untouched | Global constraint |
| Golden layout reference | Task 2 tests using local zip |

## Placeholder / consistency notes (self-review)

- Version parsing of asset names must handle line ids containing dots (`mojo-26.1`) — use `line` from matrix + extract `vN`/`shortsha` from suffix, not a single greedy split on `-`.
- `next-version.sh` must use `case "$tag" in "${line}-v"*)` not regex with unescaped dots.
- `package-driver.sh` must use env-based Python for meta.json (no broken nested heredocs).
- Meson platform flags may need per-branch fallbacks; build script includes one fallback path.

---

## Execution handoff

After this plan is accepted, implement Task 1 → Task 7 in order. Task 6 blocks on human device testing before any CI release.
