# openclaw

<p>
  <img alt="Ubuntu: tested" src="https://img.shields.io/badge/Ubuntu-tested-brightgreen?logo=ubuntu&logoColor=white">
  <img alt="Linux Mint: tested" src="https://img.shields.io/badge/Linux_Mint-tested-brightgreen?logo=linuxmint&logoColor=white">
  <img alt="CachyOS: untested" src="https://img.shields.io/badge/CachyOS-untested-lightgrey?logo=archlinux&logoColor=white">
</p>

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
versions), with each version's GitHub release notes shown beside the list —
`PgDn`/`PgUp` scrolls them, and `latest` shows the notes of the release it
resolves to. Then, once:

```bash
openclaw onboard          # pick a model provider, name your agent, set up channels
```

## Exported commands

| Command | What it does |
|---|---|
| `openclaw` | The full CLI. `openclaw --help` lists every subcommand. |
| `openclaw-gateway` | Runs the Gateway in the foreground (Ctrl-C stops it). Also a **OpenClaw Gateway** desktop entry. |
| `openclaw-node` | Runs a **node host** in the foreground — joins this machine to a gateway as a peripheral. Also a **OpenClaw Node** desktop entry. |
| `openclaw-service` | `install` / `uninstall` / `status` for the Gateway, or `node install …` for a node host. Host systemd user service. |
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

## Running a mesh (one gateway, many devices)

OpenClaw splits into two roles, and a machine runs one or the other:

| Role | Responsibility |
|---|---|
| **Gateway** | Owns every messaging channel (WhatsApp, Telegram, Discord…), runs the model, routes tool calls, serves the Control UI. **One per host, one per mesh.** |
| **Node** | A *peripheral* paired to that gateway. Exposes a command surface on its own machine — `system.run`/`system.which`, camera, screen recording, location, notifications, and a zero-config browser proxy. |

Nodes are not gateways: they never run the gateway service, and channel messages
always land on the gateway. A node is how you let the agent run commands on a
build server, NAS or second desktop while the model and your WhatsApp session
stay in one place.

### This machine as the gateway

`openclaw-service install`, as above. To accept nodes from **other machines** you
must give the gateway a reachable address — the default loopback pin is not
enough, and `openclaw devices join-code` will say so:

> `Gateway is only bound to loopback. Set gateway.bind=lan, enable tailscale serve, or configure plugins.entries.device-pair.config.publicUrl.`

Pick one:

```bash
# LAN bind. Read the security note under Networking first.
printf 'OPENCLAW_BIND=lan
' >> ~/.openclaw/gateway.env
openclaw-service uninstall && openclaw-service install

# Or keep loopback and reach it over Tailscale Serve, or an SSH tunnel
# from each node:  ssh -N -L 18790:127.0.0.1:18789 user@gateway-host
```

Then mint a join code and approve what connects:

```bash
openclaw devices join-code          # prints an `openclaw connect <url>` command
openclaw nodes pending
openclaw nodes approve <nodeRequestId>
openclaw nodes list
```

### This machine as a node

Pair once in the foreground — the setup link is single-use and expires after ten
minutes, so it must not go into a service unit:

```bash
openclaw-node --pair "oc-pair://<setup-code>" --display-name "Halo Desk"
```

Pairing state lands in `~/.openclaw/state`, which is shared `$HOME`, so once
that succeeds you can hand the connection to a service:

```bash
openclaw-service node install --host <gateway-host> --port 18789 --display-name "Halo Desk"
openclaw-service node status
openclaw-service node uninstall
```

If the gateway needs a token, put it in `~/.openclaw/node.env` rather than the
unit file — both roles read an optional `EnvironmentFile`:

```bash
printf 'OPENCLAW_GATEWAY_TOKEN=%s
' "<token>" > ~/.openclaw/node.env
chmod 600 ~/.openclaw/node.env
```

Note that `openclaw gateway install` and `openclaw node install` are **blocked**
in this container — they generate a unit naming container-only paths that the
host's manager cannot start. Use `openclaw-service` instead, or set
`OPENCLAW_ALLOW_NATIVE_SERVICE=1` if you know what you are doing.

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

- **`openclaw gateway install` / `openclaw node install` are blocked here.** Both
  generate a systemd unit pointing at container-only paths, which the host's user
  manager cannot start. `openclaw onboard` is steered away from installing one
  too. Use `openclaw-service install` / `openclaw-service node install` instead.
- **Updating**: re-run `tools setup openclaw` (optionally picking a newer release
  in the wizard). Do not use `openclaw update` — it rewrites the npm install
  inside the container and replaces the wrapper that pins the container's Node.
- **The dashboard launcher needs `flatpak` on the host.** It opens the browser
  through `distrobox-host-exec`, which silently does nothing if `flatpak` is
  missing. `openclaw-dashboard --print` always works; paste the URL yourself.
- Requires Node `>=24.16 <25` or `>=26.1`; the image ships Node 24 LTS and the
  wrappers pin it explicitly.
