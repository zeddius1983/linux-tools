// Lists whatever local LLM servers are running as OpenCode providers, with the
// models they have loaded and their real context size. One provider per port,
// re-checked every 30 seconds. See apps/opencode/README.md.
//
// Installed to ~/.config/opencode/plugins by /usr/bin/opencode, which overwrites
// it from the image: to change the ports, use local-discover.json, not this file.

import { Model, Plugin, Provider } from "@opencode/plugin"
import { readdirSync, readFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

// llama.cpp and Strata (8080) in the first range; FastFlowLM's own default, 52625,
// and the ports llmctl moves on to when it is taken, in the second.
const DEFAULT_PORTS = "8000-8099,52625-52634"
const REFRESH_MS = 30_000
const PROBE_TIMEOUT_MS = 2_000
const FALLBACK_CONTEXT = 32768

interface FoundModel {
  id: string
  apiID: string
}

interface Server {
  port: number
  label: string
  context: number
  models: FoundModel[]
}

interface Session {
  port: number
  started_unix: number
  command: string[]
}

function parsePorts(spec: string) {
  const ports = new Set<number>()
  for (const part of spec.split(",")) {
    const match = /^\s*(\d+)(?:\s*-\s*(\d+))?\s*$/.exec(part)
    if (!match) continue
    const first = Number(match[1])
    const last = Number(match[2] ?? match[1])
    for (let port = first; port <= Math.min(last, 65535); port++) ports.add(port)
  }
  return ports
}

function configuredPorts() {
  const configHome = process.env.XDG_CONFIG_HOME || join(homedir(), ".config")
  try {
    const file = join(configHome, "opencode", "local-discover.json")
    const ports = JSON.parse(readFileSync(file, "utf8")).ports
    if (typeof ports === "string") return parsePorts(ports)
  } catch {}
  return parsePorts(DEFAULT_PORTS)
}

// llmctl's newest session on each port. llmctl can use any port, so these are
// scanned too; whether one is still alive is left to the probe.
function llmctlSessions() {
  const dir = join(homedir(), ".local/state/llmctl/sessions")
  const sessions = new Map<number, Session>()
  let files: string[] = []
  try {
    files = readdirSync(dir)
  } catch {
    return sessions
  }
  for (const file of files) {
    try {
      const record = JSON.parse(readFileSync(join(dir, file), "utf8")) as Session
      const known = sessions.get(record.port)
      if (!known || record.started_unix > known.started_unix) sessions.set(record.port, record)
    } catch {}
  }
  return sessions
}

function flagValue(session: Session | undefined, flags: string[]) {
  const index = session?.command.findIndex((arg) => flags.includes(arg)) ?? -1
  return index >= 0 ? session?.command[index + 1] : undefined
}

function get(url: string) {
  return fetch(url, { signal: AbortSignal.timeout(PROBE_TIMEOUT_MS) })
}

async function getJSON(url: string): Promise<any> {
  const res = await get(url)
  if (!res.ok) throw new Error(`${url}: ${res.status}`)
  return res.json()
}

function shortName(id: string) {
  return id.split("/").pop()!.replace(/\.gguf$/, "")
}

async function probe(port: number, session: Session | undefined, previous: Server | undefined) {
  const base = `http://127.0.0.1:${port}`
  try {
    const res = await get(`${base}/v1/models`)
    if (!res.ok) return undefined
    const cards: any[] | undefined = ((await res.json()) as any)?.data
    if (!Array.isArray(cards) || !cards.length) return undefined

    const owner = cards[0]?.owned_by
    // OpenCode's own vLLM discovery already lists these.
    if (owner === "vllm") return undefined

    let loaded = cards.map((card) => String(card.id))
    let label = `Local server (port ${port})`
    let context: number | undefined

    if (owner === "FastFlowLM") {
      // /v1/models is its whole catalog; /api/ps is the one model it has loaded.
      label = `FastFlowLM (port ${port})`
      const running: any = await getJSON(`${base}/api/ps`)
      const names = (running?.models ?? []).map((model: any) => String(model.name))
      const serve = session?.command.indexOf("serve") ?? -1
      loaded = names.length ? names : serve >= 0 ? [session!.command[serve + 1]] : []
      context = Number(flagValue(session, ["--ctx-len"])) || undefined
    } else if (res.headers.get("server")?.toLowerCase() === "llama.cpp") {
      label = `llama.cpp (port ${port})`
      const props: any = await getJSON(`${base}/props`).catch((error) => {
        // Left to the handler below: guessing the size here could advertise more
        // context than the server has.
        if (error?.name === "TimeoutError") throw error
      })
      context = props?.default_generation_settings?.n_ctx
    }

    if (!loaded.length) return undefined
    return {
      port,
      label,
      context: context ?? (Number(cards[0]?.meta?.n_ctx) || FALLBACK_CONTEXT),
      models: loaded.map((apiID) => ({ id: shortName(apiID), apiID })),
    }
  } catch (error) {
    // A server busy generating can be too slow to answer. It is still there, and
    // dropping its models here would pull them out from under a running session.
    return (error as Error)?.name === "TimeoutError" ? previous : undefined
  }
}

async function scan(previous: Server[]) {
  const sessions = llmctlSessions()
  const ports = new Set([...configuredPorts(), ...sessions.keys()])
  const known = new Map(previous.map((server) => [server.port, server]))
  const results = await Promise.all(
    [...ports].sort((a, b) => a - b).map((port) => probe(port, sessions.get(port), known.get(port))),
  )
  return results.filter((server): server is Server => server !== undefined)
}

export default Plugin.define({
  id: "linux-tools.local-discover",
  async setup(ctx) {
    let servers = await scan([])

    await ctx.provider.transform((editor) => {
      for (const server of servers) {
        const providerID = Provider.ID.make(`local-${server.port}`)
        const models = server.models.map((model) => {
          const base = Model.Info.default(providerID, Model.ID.make(model.id))
          return {
            ...base,
            modelID: model.apiID,
            name: model.id,
            capabilities: { ...base.capabilities, tools: true, input: ["text"] },
            limit: {
              ...base.limit,
              context: server.context,
              output: Math.min(16384, Math.floor(server.context / 4)),
            },
          }
        })
        editor.add({
          info: {
            ...Provider.Info.empty(providerID),
            name: server.label,
            activation: "enabled",
            package: "@opencode/ai/providers/openai-compatible",
            settings: { baseURL: `http://127.0.0.1:${server.port}/v1` },
          },
          models,
        })
      }
    })

    const refresh = async () => {
      const next = await scan(servers)
      if (JSON.stringify(next) === JSON.stringify(servers)) return
      servers = next
      await ctx.provider.reload()
    }

    const timer = setInterval(() => void refresh().catch(console.error), REFRESH_MS)
    return () => clearInterval(timer)
  },
})
