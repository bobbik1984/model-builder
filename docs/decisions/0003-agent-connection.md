# 0003: How the plugin connects to an agent

- **Status:** accepted (user, 2026-11-08); implementation from M1b
- **Date:** 2026-11-08
- **Builds on:** 0002 (Python bridge = MCP server + localhost socket to the host)

## Context
Users already run agents on their own machine: Claude Code, Codex, Antigravity (`agy`), DeepSeek-based harnesses, and others. Some have only an API key. The person works in SketchUp: circle the area, type, press **Send**. The answer must come back to SketchUp. Studies (`docs/studies/park-handoff.md`, `facade-handoff.md`) showed that agents need more than modelling ops: they read files and images, run scripts and do Python analysis. Each task used ~225–250k tokens.

## Decision
The bridge stays in the middle for every option. It is started by the plugin when SketchUp opens, and it provides the same MCP tools, scope validation and proposals to every agent. The plugin settings offer **two ways to connect**, selectable per task from a dropdown next to Send:

### A. Agent program (executable)
- Fields: **Agent preset** (Claude Code / Codex / Antigravity / Custom), **Executable path** (Browse, Detect on PATH), **Command template**, **Working dir**, **Conversation mode** (new session per task / continue session; "attach project notes" on/off), **Test connection** (runs "call get_context, reply OK").
- Example template: `claude -p {prompt_file} --mcp-config {bridge_config} --output-format stream-json` (+ `--resume {session}` when continuing). Placeholders: `{prompt_file}`, `{bridge_config}`, `{session}`, `{project_notes}`, `{workdir}`.
- The agent uses its own login/subscription; the plugin stores no credentials for it.
- **Fallback for agents with no headless mode** (to check per agent, e.g. `agy`): "agent already open". The user starts the agent once with the bridge's MCP config, and it waits on `next_task`; Send fills that queue. The panel shows "no agent connected" if nobody is waiting.

### B. Direct API
- Fields: **Provider** (Anthropic / OpenAI-compatible: DeepSeek, OpenAI, local / Google Gemini), **Base URL** (OpenAI-compatible only), **Model**, **API key**, **Budget per task** (max tokens, warn at %), **Test** (must pass tool calling + image input, otherwise refuse clearly).
- **Keys live in user environment variables**, using the standard names so other tools on the machine can use them too: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` + `OPENAI_BASE_URL`, `DEEPSEEK_API_KEY` (+ `DEEPSEEK_BASE_URL`), `GEMINI_API_KEY`.
  - If one already exists, settings shows it (masked, e.g. `sk-…3f9a`) and needs no typing.
  - **Save** writes user (not system) variables (`HKCU\Environment`, no admin) and broadcasts the change. The plugin reads the value back from the registry, so no SketchUp restart is needed; the bridge gets it in its environment at start.
  - The plugin stores only the **variable name** in its settings, never the value. Keys never go into the .skp, packets, logs or chat history.
  - Accepted trade-off (the user's own machine): readable by any process running as that user, unencrypted. Usability first.
- The bridge runs the agent loop itself, with tools beyond modelling: the model ops, render + view image, read project files, a sandboxed Python step, and host Ruby only with user approval.

### Conversation window (both options)
An HtmlDialog panel in SketchUp is the chat, so the user never needs another window:
- **History** per model, in threads (one per task). Stored in the session folder (`threads/<id>.jsonl`) so it survives restarts and can be read by a different agent later.
- **Markup chips** (`p1`, `S1`, `r2`) in messages. A click flies the camera to the mark and highlights it.
- **Proposal cards** inline, with renders, the parameter table, and **Accept / Reject / Change…** (Change opens a reply prefilled with the parameters).
- **Agent activity collapsed** to one line ("12 steps · 3 renders · 41k tokens · $0.38"); click to expand. Streamed live (stream-json for CLIs, SSE for APIs).
- **Thread mode:** continue (keeps context) or fresh + project notes (`<model>.project.md`, see `samples/models/20260330_Massing.project.md`). Both are offered on purpose so they can be compared.
- Every run logs agent, model, tokens, time, and whether the restatement was confirmed, so agents can be compared.

## Consequences
- One package and protocol for every agent; only launchers differ. A new agent needs at most a preset (or none: Custom).
- Build order: bridge → Option A with the Claude Code preset → Custom → chat panel (history, chips, cards) → Option B with Anthropic → OpenAI-compatible (DeepSeek) → Gemini.
- Open checks: headless support and flags for `agy` and Codex; image input over MCP per client (otherwise pass file paths).
