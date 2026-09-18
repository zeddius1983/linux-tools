#!/usr/bin/env bash
#
# Build the release artifacts for a tag.
#
#   scripts/package.sh v2026.09.1 [outdir]
#
# Produces, in outdir (default: dist/):
#
#   linux-tools-linux-amd64.tar.gz
#   linux-tools-linux-arm64.tar.gz
#   SHA256SUMS
#
# The version is deliberately NOT in the asset name. /releases/latest/download/
# requires the exact filename, so a versioned name would mean the installer has
# to discover the version before it can download anything. With a fixed name,
# "latest" and a pinned tag are the same URL with a different middle, and the
# version travels inside the tarball as the VERSION file — which is also what
# `tools version` reports and what names the install directory.
#
# Contents come from `git archive`, so a release contains exactly what is
# committed at the tag: no stray build output, no local edits.

set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$ROOT"

TAG="${1:-}"
OUT="${2:-$ROOT/dist}"

[[ -n "$TAG" ]] || { echo "usage: scripts/package.sh <tag> [outdir]" >&2; exit 1; }
[[ "$TAG" =~ ^v?[0-9]{4}\.[0-9]{2}\.[0-9]+$ ]] \
    || { echo "error: '$TAG' is not a CalVer tag (want vYYYY.MM.N)" >&2; exit 1; }

VERSION="${TAG#v}"
ARCHES=(amd64 arm64)

# Paths that exist for developing linux-tools, not for running it.
EXCLUDE=(.github .claude .codex .firecrawl)

command -v go &>/dev/null || { echo "error: go is required to build the dashboard" >&2; exit 1; }

say() { printf '==> %s\n' "$*"; }

rm -rf "$OUT"
mkdir -p "$OUT"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# ── 1. The tree, as committed ────────────────────────────────────────────────

say "Staging the tree at $(git rev-parse --short HEAD)"
mkdir -p "$STAGE/tree"
git archive --format=tar HEAD | tar -x -C "$STAGE/tree"

for path in "${EXCLUDE[@]}"; do
    rm -rf "${STAGE:?}/tree/${path}"
done

# The marker that makes this a release install: it switches `tools` over to the
# versioned layout, stops the dashboard being rebuilt from source, and is what
# `tools version` prints.
printf '%s\n' "$VERSION" > "$STAGE/tree/VERSION"

# ── 2. The dashboard, one static binary per arch ─────────────────────────────

# CGO_ENABLED=0 is not optional here any more than it is in tools.sh: it is what
# makes the binary run on a host whose libc nobody asked about.
for arch in "${ARCHES[@]}"; do
    say "Building the dashboard for linux/$arch"
    ( cd tui && CGO_ENABLED=0 GOOS=linux GOARCH="$arch" \
        go build -trimpath -ldflags "-s -w -X main.version=$VERSION" \
        -o "$STAGE/tools-tui-$arch" . )
done

# ── 3. One tarball per arch ──────────────────────────────────────────────────

# Fixed ownership and timestamps so two builds of the same commit produce the
# same bytes; the timestamp is the commit's, not "now".
SOURCE_DATE="$(git log -1 --format=%cI HEAD)"
TAR_FLAGS=(--owner=0 --group=0 --numeric-owner --sort=name --mtime="$SOURCE_DATE")

for arch in "${ARCHES[@]}"; do
    say "Packaging linux-tools-linux-$arch.tar.gz"
    rm -rf "$STAGE/pkg"
    cp -a "$STAGE/tree" "$STAGE/pkg"
    install -m 0755 "$STAGE/tools-tui-$arch" "$STAGE/pkg/tui/tools-tui"
    tar -czf "$OUT/linux-tools-linux-$arch.tar.gz" \
        "${TAR_FLAGS[@]}" \
        --transform "s,^pkg,linux-tools," \
        -C "$STAGE" pkg
done

# ── 4. Checksums ─────────────────────────────────────────────────────────────

say "Writing SHA256SUMS"
( cd "$OUT" && sha256sum ./*.tar.gz | sed 's|\./||' > SHA256SUMS )

echo
say "linux-tools $VERSION"
( cd "$OUT" && ls -lh -- *.tar.gz SHA256SUMS | sed 's/^/    /' )
