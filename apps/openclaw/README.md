# openclaw

[OpenClaw](https://openclaw.ai/) is an open-source personal AI agent. It runs a
long-lived **Gateway** — a WebSocket/HTTP control plane with a web Control UI,
persistent memory, and OpenAI-compatible endpoints — plus an `openclaw` CLI. You
talk to your agent from WhatsApp, Telegram, Discord, a terminal UI, or the
browser dashboard, and it runs on your machine with your own model provider.

## Install

```bash
tools setup openclaw
```

The setup wizard offers a release to pin (`latest`, or one of the recent tagged
versions). Then, once:

```bash
openclaw onboard          # pick a model provider, name your agent, set up channels
```

## Exported commands

| Command | What it does |
|---|---|
| `openclaw` | The full CLI. `openclaw --help` lists every subcommand. |
| `openclaw-gateway` | Runs the Gateway in the foreground (Ctrl-C stops it). Also a **OpenClaw Gateway** desktop entry. |
| `openclaw-service` | `install` / `uninstall` / `status` — runs the Gateway as a host systemd user service. |
| `openclaw-dashboard` | Opens the Control UI in a browser on the host. Also a **OpenClaw Dashboard** desktop entry. |
| `openclaw-chat` | Terminal chat UI (`openclaw tui`). Also a **OpenClaw Chat** desktop entry. |

### Running the gateway

Foreground, for a quick session or to watch the logs:

```bash
openclaw-gateway                       # binds 127.0.0.1:18789
OPENCLAW_GATEWAY_PORT=19000 openclaw-gateway
OPENCLAW_BIND=lan openclaw-gateway     # deliberately expose it; see Networking
```

Always-on, which is how OpenClaw is meant to be used — it can only answer your
messages while it is running:

```bash
openclaw-service install
openclaw-service status
openclaw-service uninstall
```

`install` writes `~/.config/systemd/user/openclaw-gateway.service` and enables it.
The unit runs on the **host** and enters the box to start the gateway, so it keeps
working across `tools setup openclaw` rebuilds.

If `openclaw-service install` tells you lingering is off, run this **on the host**,
once — without it a user service stops at logout and does not start at boot:

```bash
loginctl enable-linger $USER
```

Gateway logs, wherever it is running:

```bash
openclaw logs --follow
```

### Control UI

```bash
openclaw-dashboard             # open it
openclaw-dashboard --print     # just print the URL
```

Each launch mints a fresh single-use, ten-minute pairing link, so the URL cannot
be bookmarked — run the command again instead. If `chrome-box` is installed the
UI opens as an app-mode Chrome window with its own profile; otherwise it goes to
your default browser.

## Storage

Everything lives in `~/.openclaw` — config, agent memory, sessions, the SQLite
state database. Distrobox shares `$HOME`, so this survives `tools setup openclaw`
(which rebuilds the image and box from scratch) and is readable from the host.

The Chrome profile used by `openclaw-dashboard` is at `~/.openclaw/chrome-profile`.

## Networking

The Gateway listens on port **18789** by default. Distrobox boxes run with
`--network host`, so it is reachable at `http://localhost:18789` from the host
with no port forwarding.

`openclaw-gateway` pins `--bind loopback`. This is deliberate: OpenClaw detects
that it is in a container and *defaults to `bind=auto`, i.e. `0.0.0.0`*, on the
assumption that a container needs to be reachable through a port forward. With
host networking there is no forward to serve, so that default would publish your
agent and its Control UI to the whole LAN. Set `OPENCLAW_BIND` to override this
if you actually want remote access — and read
[Security hardening](https://docs.openclaw.ai/gateway/security) first.

## Notes

- **`openclaw gateway install` is not the supported route here.** It generates a
  systemd unit pointing at container-only paths, which the host's user manager
  cannot start. `openclaw onboard` is steered away from it automatically; use
  `openclaw-service install` instead.
- **Updating**: re-run `tools setup openclaw` (optionally picking a newer release
  in the wizard). Do not use `openclaw update` — it rewrites the npm install
  inside the container and replaces the wrapper that pins the container's Node.
- **The dashboard launcher needs `flatpak` on the host.** It opens the browser
  through `distrobox-host-exec`, which silently does nothing if `flatpak` is
  missing. `openclaw-dashboard --print` always works; paste the URL yourself.
- Requires Node `>=24.16 <25` or `>=26.1`; the image ships Node 24 LTS and the
  wrappers pin it explicitly.
