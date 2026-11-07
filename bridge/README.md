# Bridge

A Python MCP server that sits between the agent (Claude) and the host plugins. It owns the protocol, op validation, scope enforcement and proposal state. See `../docs/architecture.md`.

## Planned layout
```
bridge/
  pyproject.toml                 # uv project, entry point: model-builder-bridge
  src/model_builder_bridge/
    __main__.py                  # CLI: --port, --session-dir
    mcp_server.py                # MCP tools/resources (stdio)
    host_link.py                 # TCP listener, JSON-RPC NDJSON to the host
    packets.py                   # load/validate context packets (protocol/schemas)
    ops.py                       # op definitions + scope validation
    proposals.py                 # proposal state machine
  tests/
    fake_host.py                 # scripted host client for tests
```

## Rules
- Never print to stdout, because it is the MCP channel. Log to stderr.
- Validate every incoming packet and outgoing op against `protocol/schemas/`.
- Must be runnable and testable without SketchUp or Rhino.
