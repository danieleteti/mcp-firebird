# Public Release v0.1.0 — Design

**Date:** 2026-07-08
**Status:** Approved (design), pending implementation
**Target:** First public release of `mcp-firebird` on https://github.com/danieleteti/mcp-firebird

## Goal

Bring the repository to a state fit for its first public release. Two objectives, held together:

1. **Be genuinely useful on its own** — a complete, documented MCP server for Firebird 2.5–5.0.
2. **Be a showcase for [`mcp-server-delphi`](https://github.com/danieleteti/mcp-server-delphi)** — a real, non-trivial reference project that demonstrates what the framework builds.

## Decisions (locked)

| Decision | Choice |
|---|---|
| License | **Apache-2.0** (matches DMVCFramework / mcp-server-delphi; patent grant) |
| Release scope | **Full polish** |
| Release artifact | **Source-only** (no prebuilt `.exe`; needs Delphi 13 to build) |
| Framework credit | **Prominent** — README hero + dedicated "How it uses mcp-server-delphi" section |
| CI | **Hygiene checks only** (no Delphi/Firebird on runner) |
| Badge "powered by mcp-server-delphi" | **Yes** |
| Community files | **All** (CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, issue/PR templates) |
| Logo | In README header + mono icon variants (already produced) |

## Work items

### 1. Legal — Apache-2.0

- **`LICENSE`** at repo root: full Apache-2.0 text, copyright `Copyright 2026 Daniele Teti`.
- **`NOTICE`**: product copyright + attribution of upstream Apache-2.0 dependencies
  (mcp-server-delphi, DMVCFramework, LoggerPro) with repo links.
- **SPDX header** (short, 3 lines) at the top of every production source unit — `sources/*.pas`,
  `providers/*.pas`, `app/*.pas`, `app/*.dpr`:
  ```pascal
  // SPDX-License-Identifier: Apache-2.0
  // Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
  // Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
  ```
  **Not** applied to `tests/**` (noise, not distributed as the product).
- Verified inserted above `unit <Name>;` / `program <Name>;`, before any code — never inside `uses`.

### 2. Showcase for mcp-server-delphi

- **README hero**: `docs/logo.png` (centered, width ~360) above the title.
- **Badges row** under the title: License (Apache-2.0), MCP protocol version (`2025-03-26`),
  and a **"powered by mcp-server-delphi"** badge linking to the framework repo.
- **Opening blockquote** right after the intro paragraph:
  > Built with **[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi)** — this
  > server is a complete, real-world example of what you can build with the framework.
- **New README section "How it uses mcp-server-delphi"** (placed after Architecture, before Tool
  reference): a real, unedited snippet from `providers/FirebirdToolsU.pas` showing the
  `[MCPTool]` / `[MCPParam]` attribute pattern, one line each on prompts (`FirebirdPromptsU`) and
  resources (`FirebirdResourcesU`), and a link to the framework for the full attribute reference.
  Educational — does not duplicate the Architecture section.
- **README footer**: link to the framework repo alongside the License section.

### 3. Clean up AGENTS.md

`AGENTS.md` currently holds unrelated "GestioneClienti" course content (SQLite/PostgreSQL stack,
rules that don't apply here) and is pulled into `CLAUDE.md` via `@AGENTS.md` — so it would ship
publicly as-is. **Rewrite it** for this project:

- Real stack: Delphi 13 + FireDAC + `fbclient`, DMVCFramework + mcp-server-delphi.
- Conventions already in force: `TAdvisory` shape, the `sources/` ↔ `MVCFramework` boundary,
  read-only default (`firebird.allow_ddl`), `try/finally` + `.Free` (no `FreeAndNil`), stdout
  reserved for JSON-RPC.
- Real build/test commands (from CLAUDE.md).
- `CLAUDE.md` keeps including it via `@AGENTS.md`.

### 4. Community files

- **`CONTRIBUTING.md`** — build prerequisites (Delphi 13 + sibling `mcp-server-delphi` /
  DMVCFramework checkouts), how the test matrix runs (FB 2.5–5.0 via `tests/`), the
  `invoke boundary` rule, commit-message style.
- **`CODE_OF_CONDUCT.md`** — Contributor Covenant 2.1, contact `d.teti@bittime.it`.
- **`SECURITY.md`** — how to report a vulnerability (private, to the maintainer email), and the
  reminder that the server is read-only by default (DDL gated behind `firebird.allow_ddl`).
- **`.github/ISSUE_TEMPLATE/bug_report.md`** — Firebird version, MCP client, relevant log excerpt,
  repro steps.
- **`.github/ISSUE_TEMPLATE/feature_request.md`** — problem, proposal, alternatives.
- **`.github/PULL_REQUEST_TEMPLATE.md`** — checklist: tests green, boundary OK, no stdout pollution,
  docs updated, SPDX header on new sources.

### 5. CI — hygiene checks (no Delphi)

`.github/workflows/ci.yml` on `ubuntu-latest` — GitHub ships PowerShell (`pwsh`) on Ubuntu, so:

- **SPDX check**: every `sources/**.pas`, `providers/**.pas`, `app/**.pas`, `app/**.dpr` begins with
  the SPDX header. Fail listing any file missing it.
- **Secret scan**: no real `.env` committed (only `bin/.env.example`); no obvious credentials.
- **Boundary check**: run `tests/check_core_boundary.ps1` via `pwsh` (no Delphi needed — it greps
  `sources/*.pas` for `MVCFramework.*` imports).
- **CI badge** added to README.

Delphi 13 is commercial and the FB matrix needs a Firebird server, so **compiled build/tests are
not run on GitHub-hosted runners** — that would require a licensed self-hosted runner. Documented as
such; contributors run the full suite locally per `CLAUDE.md`.

### 6. README finish + versioning

- **License section** at the bottom: Apache-2.0 + link to `NOTICE`.
- **`CHANGELOG.md`** (Keep a Changelog format) with a `0.1.0` entry summarizing shipped tools,
  engine support, and read-only scope.
- The GitHub **Release/tag `v0.1.0`** is created by the maintainer manually when ready —
  this work does **not** push tags or publish a release, and does **not** `git push`.

### 7. Logo assets (done)

Produced and kept in `docs/`:

| File | Use |
|---|---|
| `docs/logo.png` | Color lockup (white bg) — README header |
| `docs/logo-icon-dark.png` | Navy silhouette (transparent) — light bg, favicon |
| `docs/logo-icon-light.png` | White silhouette (transparent) — dark mode, social preview |

The raw generator output `docs/Gemini_Generated_Image_*.png` (baked checkerboard) is **deleted** —
not committed.

## Out of scope (YAGNI)

- Prebuilt binary / `fbclient` redistribution (source-only release).
- Compiled build/test in CI.
- Website / GitHub Pages.
- Multi-language README.
- Copyright headers in `tests/**`.

## Success criteria

- `LICENSE` + `NOTICE` present; every production source carries the SPDX header (CI-enforced).
- README opens with logo + badges, credits mcp-server-delphi prominently, and has a working
  "How it uses mcp-server-delphi" snippet.
- `AGENTS.md` describes *this* project, not the course example.
- All community files present; issue/PR templates render on GitHub.
- CI workflow passes on a clean checkout (hygiene checks green).
- `CHANGELOG.md` has a `0.1.0` entry.
- No secrets, no generator scratch files, no build artifacts committed.
- No `git push` / tag / release performed by this work.
