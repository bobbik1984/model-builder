# 0002: Transport: Python MCP bridge + localhost NDJSON socket

- **Status:** accepted (revisit after M1)
- **Date:** 2026-11-07

## Context
The agent (Claude via Claude Code/Desktop) connects to tools over MCP. Host plugins run inside SketchUp (Ruby, single-threaded) and Rhino (Python/.NET). We want one place for logic and validation.

## Decision
- A separate **Python bridge** process is the MCP server (stdio) for the agent.
- The bridge **listens** on `127.0.0.1:8765`. Host plugins connect as **clients** using JSON-RPC 2.0 over newline-delimited JSON.
- Images and large data are passed by **file path** in a shared session folder, not inside socket messages.

## Alternatives considered
- **MCP server inside SketchUp Ruby:** this would couple everything to Ruby, duplicate logic for Rhino, and fight the single-threaded UI.
- **HTTP server in the host:** this has the same threading problems in SketchUp, and the host would have to be the server.
- **File-based mailbox:** simple, but slow and awkward for request/response.

## Consequences
- The bridge's life depends on the MCP client, so the host must reconnect automatically and show its status.
- In SketchUp the socket is polled with `UI.start_timer` and `read_nonblock`.
- The bridge can be tested on any OS with a fake host client.
