---
name: linux-tools-guidelines
description: Project-specific development guidance for the linux-tools repository. Use when Codex is working in this repo on app packaging, Distrobox containers, tools.sh behavior, exports, README or ROADMAP updates, app memory files, Dockerfiles, wrapper scripts, or any code/documentation change that should follow the repository's CLAUDE.md rules.
---

# Linux Tools Guidelines

## Overview

Use the repository's `CLAUDE.md` as the source of truth for project conventions before changing files in linux-tools. The file captures operational rules for Distrobox packaging, app structure, documentation updates, and known pitfalls.

## Required Context

Before making code or documentation changes, read the repository root `CLAUDE.md` completely. From this skill directory, the relative path is `../../../CLAUDE.md`; from the repository root, use `CLAUDE.md`.

Treat `CLAUDE.md` as authoritative when it conflicts with general habits or assumptions. Re-read relevant sections when touching:

- `apps/<name>/` contents, especially `Dockerfile`, `exports`, `description`, `README.md`, `create_flags`, `post-install`, icons, and `.memory.md`.
- `tools.sh`, `lib/`, `completion/`, `Makefile`, or command behavior.
- Host/container execution paths that may need `distrobox-host-exec`.
- Main `README.md`, app README files, or `ROADMAP.md`.

## Workflow

1. Read `CLAUDE.md` before edits.
2. If modifying an existing app, read `apps/<name>/.memory.md` before changing that app.
3. Apply the repository's app layout, export type, wrapper script, image naming, and Distrobox host-execution rules from `CLAUDE.md`.
4. Keep required docs current: app `.memory.md`, app `README.md`, main `README.md`, and `ROADMAP.md` when the change affects them.
5. Validate with the repo's existing commands where practical, prefixing host-level commands with `distrobox-host-exec` when `CLAUDE.md` requires it.

## Reminders

- Do not duplicate large portions of `CLAUDE.md` here; load the current file so the skill tracks repository guideline changes.
- For new apps, ensure the required files from `CLAUDE.md` exist and the main app table links to the app README.
- For touched apps, update `.memory.md` with implementation details and pitfalls discovered during the work.
