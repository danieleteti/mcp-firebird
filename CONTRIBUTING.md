# Contributing to MCP Firebird

Thanks for your interest! This project is also a showcase for
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi).

MCP Firebird is **source-available commercial software, not open source** (see
[LICENSE](LICENSE)), and it has a paid Enterprise edition. That shapes how code
contributions work — read [Contributor terms](#contributor-terms) before opening a pull
request. Bug reports, reproductions and documentation fixes need no rights grant and are
always welcome.

## Prerequisites

- Windows x64, **Delphi 13 Athens** (RAD Studio 37.0) with FireDAC.
- **DMVCFramework** and **mcp-server-delphi** checked out as sibling projects (the `.dproj` search
  paths expect `C:\DEV\mcp-server-delphi\sources` and the DMVCFramework `sources` subfolders).
- A `fbclient.dll` (a 5.0 client connects to 2.5–5.0 servers).
- For the test matrix: Firebird zip-kits under `fb_versions/`, plus Python 3 with
  `pytest` and `invoke`.

## Build & test

Everything is driven from `tasks.py` (PyInvoke). Use it — do not call the `.ps1` and `.bat`
scripts directly; they are an implementation detail behind these tasks.

```powershell
invoke --list                # every available task
invoke build                 # build_core + build_app
invoke all                   # full matrix (FB 2.5-5.0) + boundary + Python compliance
invoke boundary              # sources/ stays free of MVCFramework and of host access
invoke spdx                  # every production source carries the SPDX header
invoke compliance            # Python stdio MCP protocol-compliance suite (on FB 5.0)
```

See `CLAUDE.md` for the per-version Firebird kit workflow (ports, seeding, single-test runs).

## Ground rules

- Keep `sources/*.pas` free of any `MVCFramework.*` import — MCP-facing code goes in `providers/*`.
- Read-only: no tool may run DDL/write SQL. The first one that needs to must introduce an
  explicit opt-in setting and enforce it.
- stdout is reserved for JSON-RPC; log to `bin/logs/` only.
- New production source files start with the SPDX header
  (`LicenseRef-PolyForm-Internal-Use-1.0.0`).
- Conventional Commit messages (`feat:`, `fix:`, `docs:`, `chore:`).
- Do not modify `.dproj`/`.groupproj`/`.dfm` by hand.
- Verify it builds and tests pass before opening a PR.

## Contributor terms

Code contributions are accepted only under the terms below. By submitting a contribution
(pull request, patch, or code in an issue) you agree that:

- You retain the copyright in your contribution.
- You grant Daniele Teti a perpetual, worldwide, non-exclusive, irrevocable, royalty-free,
  **sublicensable and transferable** licence to use, reproduce, modify, prepare derivative
  works of, publicly display and distribute your contribution **under any licence terms,
  including proprietary and commercial terms** — and specifically to include it in the paid
  Enterprise edition of this product.
- You grant an equivalent patent licence covering your contribution.
- The contribution is your original work, and you have the right to grant these rights. If
  you wrote it in the course of employment, your employer has authorised it.
- **No compensation, royalty, fee or accounting of any kind is or will be due to you** for
  any use of your contribution, including commercial use.
- To the extent permitted by applicable law, you agree not to assert moral rights in your
  contribution against Daniele Teti or against users of this product. Attribution in the
  project history is preserved.

If you cannot agree to these terms, please open an issue instead — bug reports,
reproductions and documentation fixes are welcome and require no rights grant.
