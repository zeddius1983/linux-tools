# Releasing

A release is one tag push. Everything else is CI.

```bash
git checkout main && git pull
git tag v2026.09.1
git push origin v2026.09.1
```

`.github/workflows/release.yml` then re-runs the CI checks, builds the
artifacts, installs what it built as a smoke test, and publishes a GitHub
Release with generated notes.

## Versioning

CalVer, `vYYYY.MM.N`, where `N` starts at 1 each month and counts releases
within it — `v2026.09.1`, `v2026.09.2`, `v2026.10.1`.

There is no API here to break, so SemVer would be answering a question nobody
asks. What a user wants to know is how stale their copy of `apps/` is, and a
date answers that. `scripts/package.sh` rejects a tag that is not this shape,
so a typo fails before anything is built.

**Tag often.** The maintainer runs the release install rather than a clone, so
a fix is not in `tools` until it is released. Tagging on most merges to `main`
is the intended cadence; `N` exists to be spent.

## What gets built

```
linux-tools-linux-amd64.tar.gz
linux-tools-linux-arm64.tar.gz
SHA256SUMS
```

The asset names carry no version, deliberately. `/releases/latest/download/`
requires the exact filename, so a versioned name would mean the installer had
to discover the version before it could download anything — and discovering it
means the GitHub API, which rate-limits unauthenticated callers by IP. With a
fixed name, "latest" and a pinned tag are the same URL with a different middle:

```
https://github.com/zeddius1983/linux-tools/releases/latest/download/linux-tools-linux-amd64.tar.gz
https://github.com/zeddius1983/linux-tools/releases/download/v2026.09.1/linux-tools-linux-amd64.tar.gz
```

The version travels inside the tarball instead, as a `VERSION` file at the
root. That file is load-bearing in three places: it names the install
directory, it is what `tools version` reports, and its presence is how the tree
knows it is a release install rather than a checkout (see `lib/release.sh`).

Tarball contents come from `git archive`, so a release holds exactly what is
committed at the tag — no local edits, no build output — plus `VERSION` and the
dashboard binary for that arch. `.github`, `.claude` and `.codex` are dropped.

## Building locally

```bash
./scripts/package.sh v2026.09.1 dist
./install.sh --tarball dist/linux-tools-linux-amd64.tar.gz --prefix /tmp/lt-test --no-modify-rc
```

`--prefix` keeps a test install away from the real one; `--tarball` skips the
download entirely, which is also how CI smoke-tests the installer without a
published release to point at.

`package.sh` archives **HEAD**, not the working tree — the dashboard binary is
built from the archived tree too, so an uncommitted change cannot ship as a
binary no shipped source produces. Commit before packaging, or you will package
the wrong code.

`scripts/test-install-e2e.sh` drives the whole thing against a local stand-in
for GitHub Releases: the `latest` → tag redirect, downloading, checksum
verification, a corrupted tarball being refused, and a missing tag. It runs
under a temporary `HOME` so it cannot repoint your own `tools` command.

## The installed layout

```
~/.local/share/linux-tools/
  versions/2026.09.1/       one unpacked release
  versions/2026.10.1/
  current -> versions/2026.10.1
~/.local/bin/tools -> ~/.local/share/linux-tools/current/tools.sh
```

`tools` and the shell completion line both point through `current`, never at a
versioned directory — that is what lets an update be a symlink flip instead of
a re-wiring, and it is why `cmd_install` has to know which layout it is in.

A release tree derives its own root from where it sits (`<root>/versions/<ver>`
in `lib/release.sh`), so `--prefix` works without anything being told about it.

The last three versions are kept. Going back to one already on disk downloads
nothing:

```bash
tools update --version v2026.09.1
```

## CI

`ci.yml` runs on every PR:

| Job | What it checks |
|---|---|
| `shellcheck` | `tools.sh`, `install.sh`, `lib/`, `scripts/`, the completion script |
| `dashboard` | `gofmt`, `go vet`, `go test`, and a cross-compile for both arches |
| `app contract` | `scripts/lint-apps.sh` — the `apps/` rules from CLAUDE.md |
| `install.sh smoke test` | packages two versions, installs one, upgrades, rolls back |

`scripts/lint-apps.sh` is a **ratchet**. Rules the tree does not fully satisfy
yet carry a list of the apps that predate them (`LEGACY_NO_README`,
`LEGACY_UNQUALIFIED_FROM`), so a new violation fails while the existing ones
stay visible and counted. Fixing an app means deleting its name from the list;
the linter reports a listed app that has since complied, so the lists cannot
quietly rot. `--strict` fails on the grandfathered ones too.

## If a release goes wrong

Releases are immutable in practice — someone may already have installed one —
so fix forward with a new tag rather than retagging. Anyone affected can step
back in one command, which is the point of keeping old versions on disk:

```bash
tools update --version v2026.09.1
```
