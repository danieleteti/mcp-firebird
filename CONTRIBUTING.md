# Contributing to MCP Firebird

Thanks for your interest! This project is also a showcase for
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi).

## Prerequisites

- Windows x64, **Delphi 13 Athens** (RAD Studio 37.0) with FireDAC.
- **DMVCFramework** and **mcp-server-delphi** checked out as sibling projects (the `.dproj` search
  paths expect `C:\DEV\mcp-server-delphi\sources` and the DMVCFramework `sources` subfolders).
- A `fbclient.dll` (a 5.0 client connects to 2.5–5.0 servers).
- For the test matrix: Firebird zip-kits under `fb_versions/`, plus Python 3 with
  `pytest` and `invoke`.

## Build

```powershell
cmd /c _build_app.bat     # -> bin\MCPFirebird.exe
cmd /c _build_core.bat    # -> DUnitX core suite
```

## Tests

```powershell
pwsh tests/run_all.ps1              # full matrix (FB 2.5-5.0) + boundary + Python compliance
pwsh tests/check_core_boundary.ps1  # sources/ must not import MVCFramework.*
pwsh scripts/check_spdx.ps1         # every production source carries the SPDX header
```

See `CLAUDE.md` for the per-version Firebird kit workflow (ports, seeding, single-test runs).

## Ground rules

- Keep `sources/*.pas` free of any `MVCFramework.*` import — MCP-facing code goes in `providers/*`.
- Read-only by default: DDL/write tools must be gated behind `firebird.allow_ddl`.
- stdout is reserved for JSON-RPC; log to `bin/logs/` only.
- New production source files start with the SPDX Apache-2.0 header.
- Conventional Commit messages (`feat:`, `fix:`, `docs:`, `chore:`).
- Do not modify `.dproj`/`.groupproj`/`.dfm` by hand.
- Verify it builds and tests pass before opening a PR.

By contributing you agree your contributions are licensed under Apache-2.0.
