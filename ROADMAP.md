# Roadmap

Tracks apps packaged (or to be packaged) as Distrobox containers.

Priority order within each section: highest first.

## AI / LLM Tools

- [x] `vllm` — high-throughput OpenAI-compatible LLM inference server (ROCm)
- [ ] `open-webui` — web UI for local LLMs; works with Ollama and OpenAI-compatible APIs (https://docs.openwebui.com/)
- [ ] `ollama` — local LLM runtime (GPU-accelerated)
- [x] `lmstudio` — LM Studio local model runner
- [x] `comfyui` — node-based UI for generative AI image workflows
- [ ] `aider` — AI pair programmer CLI
- [ ] `sgpt` — ShellGPT: AI shell assistant; OpenAI + Ollama backends (https://github.com/TheR1D/shell_gpt)
- [x] `unsloth` — fast LLM fine-tuning (https://unsloth.ai/docs)
- [x] `llama-cpp-rocm` — llama.cpp LLM inference engine (ROCm + Vulkan backends, `--device` selection, multi-stage build, `llama` dispatcher + `llama-serve`)
- [ ] `openclaw` — personal AI assistant CLI + gateway; routes across AI providers, persistent memory, messaging integrations (https://openclaw.ai/)

## Development Tools

- [x] `dev-toolbox` — containerized development runtimes, CLI tools, and language servers
- [x] `claude-code` — Anthropic Claude Code CLI
- [x] `codex-cli` — OpenAI Codex CLI
- [x] `copilot-cli` — GitHub Copilot CLI
- [x] `antigravity` — Google Antigravity AI CLI (agy)
- [x] `dev-toolbox` SDKMAN/Java support — project JDK management moved out of `jetbrains-toolbox`
- [ ] `opencode` — AI coding agent CLI (https://opencode.ai/docs/ru)
- [ ] `cursor` — AI-powered code editor (Electron)
- [ ] `windsurf` — Codeium Windsurf editor
- [ ] `zed` — fast collaborative editor (GPU-rendered)
- [ ] `markitdown` — Microsoft CLI to convert Office/PDF/HTML to Markdown (https://github.com/microsoft/markitdown)
- [ ] `scrapling` — Python web scraping with anti-bot evasion (https://github.com/D4Vinci/Scrapling)

## System Monitoring / Hardware

- [x] `amdgpu_top` — AMD GPU usage monitor
- [x] `corefreq` — CPU frequency / perf monitor (kernel module build)
- [x] `nvtop` — GPU process monitor (NVIDIA / AMD), Fedora package + CDI passthrough
- [x] `nvbandwidth` — NVIDIA GPU memory-bandwidth / NVLink benchmark (CUDA build container + CDI passthrough)
- [ ] `btop` — modern resource monitor

## Browsers / Web

- [x] `chrome` — Google Chrome
- [ ] `brave` — Brave browser
- [ ] `firefox-dev` — Firefox Developer Edition

## Communication

- [x] `telegram` — Telegram desktop client

## Shell / Terminal

- [x] `shell-toolbox` — Zsh shell exported to the host, with optional utilities: fzf, bat, glow, ripgrep, eza, zoxide, fd, delta

## Tooling / Infrastructure

- [ ] Migrate the host TUI from `whiptail` to a **Go + [`huh`](https://github.com/charmbracelet/huh)** (Bubble Tea) front-end. Keep the bash `cmd_*` backend (`lib/commands.sh`) untouched — Go replaces only the menu + wizard rendering (`lib/tui.sh`, `lib/wizard.sh`) and shells out. Wins: `huh.Group` = wizard page, `huh.NewMultiSelect` = `.packages`, `huh.NewSelect` = `.buildarg`, with native multi-field forms and validation whiptail can't do; attractive default theme (fixes the checkbox/button contrast fights); instant single-`Esc`-to-quit (whiptail/newt swallows it). Ships as one static binary → host dependency is "drop a file in `~/.local/bin`," not a container concern. Suggested spike first: port just the app-selection menu + the `claude-code` statusline `.packages` page before committing to the full migration.

## Misc / Fun
