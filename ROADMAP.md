# Roadmap

Tracks apps packaged (or to be packaged) as Distrobox containers.

Priority order within each section: highest first.

## AI / LLM Tools

- [x] `vllm` — high-throughput OpenAI-compatible LLM inference server (ROCm)
- [ ] `open-webui` — web UI for local LLMs; works with Ollama and OpenAI-compatible APIs (https://docs.openwebui.com/)
- [ ] `ollama` — local LLM runtime (GPU-accelerated)
- [x] `lmstudio` — LM Studio local model runner (setup-time GPU runtime picker: AMD ROCm/Vulkan, or NVIDIA CUDA via CDI `--device nvidia.com/gpu=all`)
- [x] `comfyui` — node-based UI for generative AI image workflows
- [ ] `aider` — AI pair programmer CLI
- [ ] `sgpt` — ShellGPT: AI shell assistant; OpenAI + Ollama backends (https://github.com/TheR1D/shell_gpt)
- [x] `unsloth` — fast LLM fine-tuning (https://unsloth.ai/docs)
- [x] `llama-cpp-rocm` — llama.cpp LLM inference engine (ROCm + Vulkan backends, `--device` selection, multi-stage build, `llama` dispatcher + `llama-serve`)
- [x] `fastflowlm` — Ollama-style LLM runtime running fully on the AMD Ryzen AI NPU (XDNA2); XRT userspace from the lemonade PPA, release-picker wizard, `flm-doctor` host prerequisite check
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
- [x] `nvidia-cdi-service` — host-only boot service; regenerates the CDI spec each boot to match installed GPUs
- [x] `nvidia-acs-service` — host-only boot service; clears PCIe ACS redirect for switch-local GPU P2P (renumber-proof)
- [x] `nvidia-p2p-driver` — build/install the aikitoria GeForce-P2P-patched nvidia module (corefreq-style build container, Arch/Ubuntu)
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

- [ ] Replace the host TUI (`whiptail`) with a **Go dashboard** modelled on [`gh-dash`](https://github.com/dlvhdr/gh-dash): category tabs, an app table, and a README info panel. Built on Bubble Tea v2 / Lip Gloss v2 / Glamour — *not* `huh`, which is a form library and cannot express tabs plus a table plus a sidebar (gh-dash uses no huh either, and huh still depends on Bubble Tea v1). The bash `cmd_*` backend (`lib/commands.sh`) is untouched: actions suspend the dashboard with `tea.ExecProcess` so podman output streams normally, then it resumes. Wizard pages are native too: answers are collected in Go and handed to bash through a state file, so `whiptail` is no longer reached from the dashboard. Prototype in `tui/`, not wired in — `tools` still opens whiptail. Remaining: `cmd_install` shipping the binary, and the launch gate. Design doc: [`docs/tui-migration.md`](docs/tui-migration.md).

## Misc / Fun
