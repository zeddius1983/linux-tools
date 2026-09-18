#!/usr/bin/env bash
#
# End-to-end test of install.sh against a local stand-in for GitHub Releases.
#
# The --tarball path that CI's smoke test uses covers the layout, but it skips
# everything that involves the network: resolving "latest" through a redirect,
# building the asset URL, downloading, and verifying SHA256SUMS. Those are the
# parts a user hits first, so they are tested here against a server that mimics
# GitHub's redirect behaviour:
#
#   /releases/latest                    302 -> /releases/tag/<tag>
#   /releases/latest/download/<asset>    302 -> /releases/download/<tag>/<asset>
#   /releases/download/<tag>/<asset>     the file, or 404
#
# Everything happens under a temporary prefix and is removed afterwards; no
# release is published and the real installation is untouched.
#
# Usage: scripts/test-install-e2e.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$ROOT"

OLD="2026.08.1"
NEW="2026.09.1"

WORK="$(mktemp -d)"
PREFIX="$WORK/prefix"
SERVE="$WORK/serve"
SERVER_PID=""
PORT=""

cleanup() {
    [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null
    rm -rf "$WORK"
    return 0
}
trap cleanup EXIT

pass=0
fail=0
ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; pass=$((pass + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fail=$((fail + 1)); }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

check() {  # check <description> <expected> <actual>
    if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (want '$2', got '$3')"; fi
}

# The installed tree's own tools.sh, which is what a user would be running.
tools() { "$PREFIX/current/tools.sh" "$@"; }

# ── Build two releases and lay them out the way GitHub serves them ──────────

step "Packaging $OLD and $NEW"
for v in "$OLD" "$NEW"; do
    ./scripts/package.sh "v$v" "$WORK/dist-$v" >/dev/null
    mkdir -p "$SERVE/download/v$v"
    cp "$WORK/dist-$v"/* "$SERVE/download/v$v/"
done
ok "built both releases"

# ── A stand-in for GitHub's release endpoints ───────────────────────────────

cat > "$WORK/server.py" <<'PY'
import http.server, os, sys, posixpath

ROOT, LATEST = sys.argv[1], sys.argv[2]

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_HEAD(self): self.route()
    def do_GET(self):  self.route()

    def route(self):
        path = posixpath.normpath(self.path)
        # The redirect that lets an installer learn the newest tag without
        # touching the rate-limited API.
        if path == "/releases/latest":
            return self.redirect(f"/releases/tag/{LATEST}")
        if path.startswith("/releases/tag/"):
            return self.blank()
        if path.startswith("/releases/latest/download/"):
            asset = path.rsplit("/", 1)[-1]
            return self.redirect(f"/releases/download/{LATEST}/{asset}")
        if path.startswith("/releases/download/"):
            rest = path[len("/releases/download/"):]
            return self.serve(os.path.join(ROOT, "download", rest))
        self.send_error(404)

    def redirect(self, to):
        self.send_response(302); self.send_header("Location", to)
        self.send_header("Content-Length", "0"); self.end_headers()

    def blank(self):
        self.send_response(200); self.send_header("Content-Length", "0"); self.end_headers()

    def serve(self, fs_path):
        if not os.path.isfile(fs_path):
            return self.send_error(404)
        self.send_response(200)
        self.send_header("Content-Length", str(os.path.getsize(fs_path)))
        self.end_headers()
        if self.command == "HEAD":
            return
        with open(fs_path, "rb") as f:
            self.wfile.write(f.read())

    def log_message(self, *a): pass

http.server.HTTPServer(("127.0.0.1", int(sys.argv[3])), Handler).serve_forever()
PY

PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
python3 "$WORK/server.py" "$SERVE" "v$NEW" "$PORT" &
SERVER_PID=$!
export LT_RELEASES_URL="http://127.0.0.1:$PORT/releases"

# Wait for it to accept connections rather than guessing at a sleep.
for _ in $(seq 1 50); do
    curl -fsS -o /dev/null "$LT_RELEASES_URL/latest" 2>/dev/null && break
    sleep 0.1
done

step "Fresh install with no --version (resolves 'latest' through the redirect)"
./install.sh --prefix "$PREFIX" --no-modify-rc --skip-checks >"$WORK/log1" 2>&1 \
    || { cat "$WORK/log1"; bad "install failed"; }
check "installed the newest release" "$NEW" "$(tools version | head -1 | awk '{print $2}')"
grep -q "latest is v$NEW" "$WORK/log1" && ok "resolved the tag from the redirect" \
    || bad "did not resolve the tag from the redirect"
grep -q "Verifying checksum" "$WORK/log1" && ok "verified SHA256SUMS" \
    || bad "did not verify the checksum"

step "Pinned install of an older release"
./install.sh --prefix "$PREFIX" --version "v$OLD" --no-modify-rc --skip-checks >"$WORK/log2" 2>&1 \
    || { cat "$WORK/log2"; bad "pinned install failed"; }
check "installed the pinned release" "$OLD" "$(tools version | head -1 | awk '{print $2}')"

step "tools update returns to the newest release"
tools update >"$WORK/log3" 2>&1 || { cat "$WORK/log3"; bad "update failed"; }
check "update moved forward" "$NEW" "$(tools version | head -1 | awk '{print $2}')"

step "tools update --version rolls back without downloading"
tools update --version "v$OLD" >"$WORK/log4" 2>&1 || { cat "$WORK/log4"; bad "rollback failed"; }
check "rolled back" "$OLD" "$(tools version | head -1 | awk '{print $2}')"
grep -q "already installed" "$WORK/log4" && ok "reused the tree on disk, no download" \
    || bad "re-downloaded a version it already had"

step "tools update --check reports both versions"
out="$(tools update --check 2>&1 || true)"
grep -q "installed: $OLD" <<<"$out" && ok "reports the installed version" \
    || bad "does not report the installed version"
grep -q "latest:    v$NEW" <<<"$out" && ok "reports the latest version" \
    || bad "does not report the latest version"

step "A corrupted download is refused"
printf 'not a tarball' >> "$SERVE/download/v$NEW/linux-tools-linux-amd64.tar.gz"
if ./install.sh --prefix "$PREFIX" --version "v$NEW" --force --no-modify-rc --skip-checks \
        >"$WORK/log5" 2>&1; then
    bad "installed a tarball whose checksum does not match"
else
    grep -q "checksum mismatch" "$WORK/log5" && ok "refused on checksum mismatch" \
        || { cat "$WORK/log5"; bad "failed, but not because of the checksum"; }
fi
check "left the working install in place" "$OLD" "$(tools version | head -1 | awk '{print $2}')"

step "A tag that does not exist fails clearly"
if ./install.sh --prefix "$PREFIX" --version v2099.01.1 --no-modify-rc --skip-checks \
        >"$WORK/log6" 2>&1; then
    bad "claimed to install a release that does not exist"
else
    grep -q "no release asset at" "$WORK/log6" && ok "named the missing asset" \
        || { cat "$WORK/log6"; bad "failed without a useful message"; }
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
