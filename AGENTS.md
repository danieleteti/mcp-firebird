# Agent Rules — MCP Firebird

Shared rules for all AI agents (Claude Code, Copilot, Cursor, …) working in this repository.
`CLAUDE.md` includes this file via `@AGENTS.md`.

## What this is

An MCP (Model Context Protocol) server for Firebird 2.5–5.0, written in Delphi against the
official `fbclient` driver + FireDAC, exposing schema/plan/index analysis to AI assistants over
stdio JSON-RPC. It is also a real-world showcase for
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi).

## Stack

- Delphi 13 Athens (RAD Studio 37.0), VCL-free console app.
- FireDAC + `fbclient.dll` (a 5.0 client connects to 2.5–5.0 servers).
- DMVCFramework + `mcp-server-delphi` for the MCP attribute layer.
- DUnitX (core suite) + Python `pytest` (protocol compliance).

## Conventions

- PascalCase; classes start with `T`. Private fields prefixed `F`.
- `try/finally` with `.Free` for every allocated resource. Do **not** use `FreeAndNil`.
- Every advisory-producing function returns `TAdvisory` (Severity/Finding/SQLText/Verify).
- **Layer boundary:** `sources/*.pas` is pure Delphi/FireDAC domain logic and must **never**
  import `MVCFramework.*`. MCP-facing code lives in `providers/*`. Enforced by
  `tests/check_core_boundary.ps1`.
- **Read-only:** no tool runs DDL/write SQL. The first one that needs to must introduce an
  explicit opt-in setting and enforce it.
- **stdout is reserved for JSON-RPC.** All logging goes to `bin/logs/` via LoggerPro. Never write
  to stdout outside the MCP transport.
- New production source files carry the SPDX `LicenseRef-PolyForm-Internal-Use-1.0.0` header
  (see `scripts/check_spdx.ps1`). This project is source-available, not open source.
- Never add host access (file reads, process spawning) to `sources/` — that is the paid
  Enterprise edition's territory. `invoke boundary` enforces it.

## Build & test

- Build app: `cmd /c _build_app.bat` → `bin\MCPFirebird.exe`
- Build core tests: `cmd /c _build_core.bat`
- Full matrix + compliance: `pwsh tests/run_all.ps1`
- Boundary check: `pwsh tests/check_core_boundary.ps1`
- See `CLAUDE.md` and `CONTRIBUTING.md` for the per-version Firebird kit workflow.

## Do NOT

- Do not modify `.dproj`/`.groupproj`/`.dfm` by hand.
- Do not add an `MVCFramework` import to any `sources/*.pas` unit.
- Do not write to stdout outside the MCP transport.
- Do not `git commit`/`git push` without an explicit request.
- Do not add external dependencies without approval.
- Do not declare a task done without verifying it builds/tests.
