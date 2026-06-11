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
- [x] `llama-cpp` — llama.cpp LLM inference engine (ROCm, multi-stage build, `llama` dispatcher + `llama-serve`)
- [ ] `openclaw` — personal AI assistant CLI + gateway; routes across AI providers, persistent memory, messaging integrations (https://openclaw.ai/)

## Development Tools

- [x] `claude-code` — Anthropic Claude Code CLI
- [x] `codex-cli` — OpenAI Codex CLI
- [x] `copilot-cli` — GitHub Copilot CLI
- [x] `antigravity` — Google Antigravity AI CLI (agy)
- [ ] `opencode` — AI coding agent CLI (https://opencode.ai/docs/ru)
- [ ] `cursor` — AI-powered code editor (Electron)
- [ ] `windsurf` — Codeium Windsurf editor
- [ ] `zed` — fast collaborative editor (GPU-rendered)
- [ ] `markitdown` — Microsoft CLI to convert Office/PDF/HTML to Markdown (https://github.com/microsoft/markitdown)
- [ ] `scrapling` — Python web scraping with anti-bot evasion (https://github.com/D4Vinci/Scrapling)

## System Monitoring / Hardware

- [x] `amdgpu_top` — AMD GPU usage monitor
- [x] `corefreq` — CPU frequency / perf monitor (kernel module build)
- [ ] `nvtop` — GPU process monitor (NVIDIA / AMD)
- [ ] `btop` — modern resource monitor

## Browsers / Web

- [x] `chrome` — Google Chrome
- [ ] `brave` — Brave browser
- [ ] `firefox-dev` — Firefox Developer Edition

## Communication

- [x] `telegram` — Telegram desktop client

## Shell / Terminal

- [x] `zsh-box` — Zsh shell exported to the host, with optional utilities: fzf, bat, glow, ripgrep, eza, zoxide, fd, delta

## Misc / Fun
