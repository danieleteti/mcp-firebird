# Public Release v0.1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring `mcp-firebird` to a state fit for its first public GitHub release (v0.1.0): licensed, documented, credited to `mcp-server-delphi`, with community files and hygiene CI.

**Architecture:** Pure repository/metadata work — add legal + community + CI files, rewrite `AGENTS.md`, extend `README.md`, and stamp SPDX headers into production sources. No Delphi code logic changes. Verification is by shell command (grep/render), not compilation.

**Tech Stack:** Markdown, Apache-2.0, GitHub Actions (`ubuntu-latest` + `pwsh`), PowerShell for the boundary check.

## Global Constraints

- License: **Apache-2.0**. Copyright line: `Copyright 2026 Daniele Teti`.
- SPDX header goes on **production sources only**: `sources/*.pas`, `providers/*.pas`, `app/*.pas`, `app/*.dpr`. **Never** on `tests/**`.
- SPDX header (exact 3 lines), placed above `unit`/`program`, before any code:
  ```
  // SPDX-License-Identifier: Apache-2.0
  // Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
  // Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
  ```
- Release is **source-only**. This plan performs **no `git push`, no tag, no GitHub Release**.
- Contact email for community files: `d.teti@bittime.it`.
- MCP protocol version string: `2025-03-26`. Server version: `0.1.0`.
- Commit style: Conventional Commits (`feat:`/`docs:`/`chore:`), ending with the `Co-Authored-By` trailer already used in this repo.
- Do **not** modify `.dproj`/`.groupproj` (AGENTS.md rule).

## File map

| File | Action | Responsibility |
|---|---|---|
| `LICENSE` | create | Apache-2.0 full text |
| `NOTICE` | create | Product copyright + upstream attributions |
| `sources/*.pas`, `providers/*.pas`, `app/*.pas`, `app/*.dpr` (17 files) | modify | Prepend SPDX header |
| `AGENTS.md` | replace | Project-accurate agent rules |
| `README.md` | modify | Logo/badges hero, framework showcase section, License section |
| `CONTRIBUTING.md` | create | Build/test/contribution guide |
| `CODE_OF_CONDUCT.md` | create | Contributor Covenant 2.1 |
| `SECURITY.md` | create | Vulnerability reporting + read-only note |
| `.github/ISSUE_TEMPLATE/bug_report.md` | create | Bug template |
| `.github/ISSUE_TEMPLATE/feature_request.md` | create | Feature template |
| `.github/PULL_REQUEST_TEMPLATE.md` | create | PR checklist |
| `.github/workflows/ci.yml` | create | Hygiene CI (SPDX + secrets + boundary) |
| `scripts/check_spdx.ps1` | create | Portable SPDX-presence check (used by CI + locally) |
| `CHANGELOG.md` | create | Keep-a-Changelog, `0.1.0` entry |
| `docs/Gemini_Generated_Image_*.png` | delete | Remove generator scratch file |

---

### Task 1: LICENSE + NOTICE

**Files:**
- Create: `LICENSE`
- Create: `NOTICE`

**Interfaces:**
- Produces: `LICENSE` (Apache-2.0), `NOTICE` — referenced by README (Task 6) and SPDX headers (Task 2).

- [ ] **Step 1: Write LICENSE (canonical Apache-2.0 text)**

Write the standard Apache License 2.0 into `LICENSE`. Use the exact canonical text from https://www.apache.org/licenses/LICENSE-2.0.txt (the full ~202-line license, unmodified — do not fill the optional appendix boilerplate placeholders; leave the "APPENDIX: How to apply" section as-is). Do not paraphrase or truncate.

- [ ] **Step 2: Write NOTICE**

```
MCP Firebird
Copyright 2026 Daniele Teti

This product is licensed under the Apache License, Version 2.0 (see LICENSE).

It is a showcase for and built with:
  - mcp-server-delphi   https://github.com/danieleteti/mcp-server-delphi   (Apache-2.0)
  - DMVCFramework       https://github.com/danieleteti/delphimvcframework  (Apache-2.0)
  - LoggerPro           https://github.com/danieleteti/loggerpro           (Apache-2.0)

Firebird and the fbclient library are property of their respective owners and
are not distributed with this project.
```

- [ ] **Step 3: Verify both files exist and NOTICE names the framework**

Run: `test -f LICENSE && grep -c "Apache License" LICENSE && grep -c "mcp-server-delphi" NOTICE`
Expected: prints a non-zero count for both (LICENSE contains "Apache License"; NOTICE references the framework).

- [ ] **Step 4: Commit**

```bash
git add LICENSE NOTICE
git commit -m "docs: add Apache-2.0 LICENSE and NOTICE

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: SPDX headers in production sources

**Files:**
- Create: `scripts/check_spdx.ps1`
- Modify: `sources/*.pas` (10), `providers/*.pas` (4), `app/BootConfigU.pas`, `app/EngineConfigU.pas`, `app/MCPFirebird.dpr` (17 files total)

**Interfaces:**
- Produces: `scripts/check_spdx.ps1` — a portable checker reused by CI (Task 7). Exit 0 when all production sources carry the SPDX first line; exit 1 listing offenders otherwise.

- [ ] **Step 1: Write the SPDX checker**

Create `scripts/check_spdx.ps1`:

```powershell
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$patterns = @('sources/*.pas', 'providers/*.pas', 'app/*.pas', 'app/*.dpr')
$expected = 'SPDX-License-Identifier: Apache-2.0'
$missing = @()
foreach ($p in $patterns) {
    Get-ChildItem -Path (Join-Path $root $p) -File | ForEach-Object {
        $first = Get-Content -LiteralPath $_.FullName -TotalCount 1
        if ($first -notmatch [regex]::Escape($expected)) { $missing += $_.FullName }
    }
}
if ($missing.Count -gt 0) {
    Write-Host "Missing SPDX header in:"
    $missing | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host "SPDX OK: all production sources carry the Apache-2.0 header."
```

- [ ] **Step 2: Run the checker to verify it FAILS (headers not added yet)**

Run: `pwsh scripts/check_spdx.ps1`
Expected: exits 1, lists all 17 production source files as missing.

- [ ] **Step 3: Prepend the SPDX header to every production source**

For each of the 17 files, insert these 3 lines as the very first lines of the file (before `unit`/`program`, before any blank line or `uses`):

```
// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
```

Files (exact list, 17):
`sources/Firebird.Advisory.pas`, `sources/Firebird.Capabilities.pas`, `sources/Firebird.Connection.pas`, `sources/Firebird.DocGen.pas`, `sources/Firebird.Goal.pas`, `sources/Firebird.IndexAdvisor.pas`, `sources/Firebird.Introspection.pas`, `sources/Firebird.PlanAnalyzer.pas`, `sources/Firebird.SchemaAudit.pas`, `sources/Firebird.TransactionMonitor.pas`, `providers/FirebirdConfigU.pas`, `providers/FirebirdPromptsU.pas`, `providers/FirebirdResourcesU.pas`, `providers/FirebirdToolsU.pas`, `app/BootConfigU.pas`, `app/EngineConfigU.pas`, `app/MCPFirebird.dpr`.

(Do it with an editor per file, or the helper below. Preserve each file's existing encoding/line endings; add nothing else.)

Optional helper (Git Bash), prepend only if not already present:
```bash
HDR='// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Daniele Teti — https://github.com/danieleteti/mcp-firebird
// Part of MCP Firebird, a showcase for https://github.com/danieleteti/mcp-server-delphi
'
for f in sources/*.pas providers/*.pas app/*.pas app/MCPFirebird.dpr; do
  head -1 "$f" | grep -q 'SPDX-License-Identifier' || { printf '%s' "$HDR" | cat - "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }
done
```

- [ ] **Step 4: Run the checker to verify it PASSES**

Run: `pwsh scripts/check_spdx.ps1`
Expected: exits 0, prints "SPDX OK: all production sources carry the Apache-2.0 header."

- [ ] **Step 5: Sanity-check a header landed correctly (above `unit`)**

Run: `head -4 sources/Firebird.Connection.pas`
Expected: three `//` SPDX lines, then `unit Firebird.Connection;`.

- [ ] **Step 6: Verify the boundary check still passes (no accidental edits to `uses`)**

Run: `pwsh tests/check_core_boundary.ps1`
Expected: "Core boundary OK: no MVCFramework imports in sources/".

- [ ] **Step 7: Commit**

```bash
git add scripts/check_spdx.ps1 sources providers app
git commit -m "chore: add SPDX Apache-2.0 headers to production sources

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Rewrite AGENTS.md

**Files:**
- Modify (replace whole file): `AGENTS.md`

**Interfaces:**
- Consumes: nothing. `CLAUDE.md` already includes it via `@AGENTS.md` — that line stays unchanged.
- Produces: project-accurate agent rules visible publicly and to `CLAUDE.md`.

- [ ] **Step 1: Replace AGENTS.md entirely**

```markdown
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
- **Read-only by default:** any tool running DDL/write SQL must be gated behind
  `firebird.allow_ddl`.
- **stdout is reserved for JSON-RPC.** All logging goes to `bin/logs/` via LoggerPro. Never write
  to stdout outside the MCP transport.
- New production source files carry the SPDX Apache-2.0 header (see `scripts/check_spdx.ps1`).

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
```

- [ ] **Step 2: Verify no leftover course content remains**

Run: `grep -ci "GestioneClienti\|SQLite\|PostgreSQL" AGENTS.md`
Expected: `0`.

- [ ] **Step 3: Commit**

```bash
git add AGENTS.md
git commit -m "docs: rewrite AGENTS.md for this project (was course leftover)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: README — logo/badges hero + framework showcase

**Files:**
- Modify: `README.md` (top of file, lines 1–13; and insert a new section after `## What it does`)

**Interfaces:**
- Consumes: `docs/logo.png` (exists), framework repo URL.
- Produces: rendered hero + a "Built with mcp-server-delphi" section other tasks don't depend on.

- [ ] **Step 1: Replace the top of README (before line 15 `## Table of contents`)**

Replace the current lines 1–13 with:

```markdown
<p align="center">
  <img src="docs/logo.png" alt="MCP Firebird" width="360">
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: Apache-2.0" src="https://img.shields.io/badge/License-Apache_2.0-blue.svg"></a>
  <img alt="MCP protocol 2025-03-26" src="https://img.shields.io/badge/MCP-2025--03--26-brightgreen.svg">
  <a href="https://github.com/danieleteti/mcp-server-delphi"><img alt="powered by mcp-server-delphi" src="https://img.shields.io/badge/powered%20by-mcp--server--delphi-orange.svg"></a>
  <a href=".github/workflows/ci.yml"><img alt="CI" src="https://github.com/danieleteti/mcp-firebird/actions/workflows/ci.yml/badge.svg"></a>
</p>

# MCP Firebird

A [Model Context Protocol](https://modelcontextprotocol.io) server for **Firebird 2.5 – 5.0**,
written in Delphi with the official `fbclient` driver. It lets an AI assistant document
schemas, analyze query plans, advise on indexes (which to add **and** which to drop), audit
schema health, and drive goal-based optimization — **read-only by default**.

> Built with **[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi)** — this
> server is a complete, real-world example of what you can build with the framework.

- **Transport:** stdio (JSON-RPC 2.0, MCP protocol `2025-03-26`)
- **Server identity:** `mcp-firebird` v`0.1.0`
- **Engine support:** Firebird 2.5, 3.0, 4.0, 5.0 (capability-detected at runtime)
- **Safety:** read-only analysis; DDL/write is gated behind `firebird.allow_ddl=true`
```

(Keep the existing `---` separator and `## Table of contents` that follow.)

- [ ] **Step 2: Add "How it uses mcp-server-delphi" section**

Immediately after the `## What it does` section (before `## Prerequisites`), insert:

```markdown
## How it uses mcp-server-delphi

Every tool is a plain Delphi method decorated with attributes from
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi). The framework turns the
class into an MCP tool provider, generates the JSON-RPC schema from the attributes, and wires it
to the stdio transport — no protocol code in this repo. From `providers/FirebirdToolsU.pas`:

```pascal
TFirebirdTools = class(TMCPToolProvider)
public
  [MCPTool('fb_info', 'Engine version, dialect, charset and detected capabilities of the configured Firebird database')]
  function FbInfo: TMCPToolResult;

  [MCPTool('fb_describe_table', 'Columns, primary key, indexes and foreign keys of a table')]
  function FbDescribeTable([MCPParam('Table name')] const table_name: string): TMCPToolResult;

  [MCPTool('fb_analyze_query', 'Returns and analyzes the access plan of a SQL query (flags NATURAL scans and external sorts)')]
  function FbAnalyzeQuery([MCPParam('The SQL query to analyze')] const sql: string): TMCPToolResult;
end;
```

Prompts (`providers/FirebirdPromptsU.pas`) and resources (`providers/FirebirdResourcesU.pas`) use
the same attribute approach. See the [mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi)
repository for the full attribute reference.

---
```

- [ ] **Step 3: Verify the images and section render (links resolve locally)**

Run: `grep -c "docs/logo.png\|How it uses mcp-server-delphi\|powered%20by-mcp--server--delphi" README.md`
Expected: count ≥ 3.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs(readme): logo + badges hero and mcp-server-delphi showcase section

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: README License section

**Files:**
- Modify: `README.md` (append a `## License` section at the end)

**Interfaces:**
- Consumes: `LICENSE`, `NOTICE` (Task 1).

- [ ] **Step 1: Append at the end of README.md**

```markdown

---

## License

Licensed under the **Apache License 2.0** — see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

MCP Firebird is a showcase for
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi). If you build your own MCP
server in Delphi, start there.
```

- [ ] **Step 2: Verify**

Run: `grep -c "## License" README.md`
Expected: `1`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(readme): add License section

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Community files

**Files:**
- Create: `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`

**Interfaces:**
- Consumes: build/test facts from `CLAUDE.md`.

- [ ] **Step 1: Write CONTRIBUTING.md**

```markdown
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
```

- [ ] **Step 2: Write CODE_OF_CONDUCT.md**

Write the **Contributor Covenant v2.1** standard text (canonical text from
https://www.contributor-covenant.org/version/2/1/code_of_conduct/ ). Set the enforcement contact to
`d.teti@bittime.it`. Do not paraphrase the covenant body.

- [ ] **Step 3: Write SECURITY.md**

```markdown
# Security Policy

## Supported versions

MCP Firebird is pre-1.0; security fixes land on the latest `main`.

## Reporting a vulnerability

Please report vulnerabilities **privately** by email to **d.teti@bittime.it** — do not open a
public issue. Include repro steps, affected Firebird/engine version, and impact. You will get an
acknowledgement and a fix timeline.

## Safety model

The server is **read-only by default**. DDL and write SQL are gated behind `firebird.allow_ddl`
(off by default). It connects to a single configured database and never writes to stdout outside
the MCP transport. Treat the `.env` connection credentials as secrets — only `bin/.env.example`
is committed.
```

- [ ] **Step 4: Verify**

Run: `for f in CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md; do test -f "$f" && echo "$f ok"; done; grep -c "d.teti@bittime.it" SECURITY.md CODE_OF_CONDUCT.md`
Expected: three "ok" lines; the email appears in both files.

- [ ] **Step 5: Commit**

```bash
git add CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md
git commit -m "docs: add CONTRIBUTING, CODE_OF_CONDUCT, SECURITY

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: GitHub templates + hygiene CI

**Files:**
- Create: `.github/ISSUE_TEMPLATE/bug_report.md`, `.github/ISSUE_TEMPLATE/feature_request.md`, `.github/PULL_REQUEST_TEMPLATE.md`, `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `scripts/check_spdx.ps1` (Task 2), `tests/check_core_boundary.ps1` (exists).
- Note: `tests/check_core_boundary.ps1` hardcodes `C:\DEV\mcp-firebird\...` — CI must not call it directly. CI runs an inline portable boundary check instead (Step 4).

- [ ] **Step 1: Write bug_report.md**

```markdown
---
name: Bug report
about: Report a problem with MCP Firebird
labels: bug
---

**Describe the bug**
A clear description of what went wrong.

**Environment**
- Firebird version: (2.5 / 3.0 / 4.0 / 5.0)
- MCP client: (Claude Desktop / Claude Code / Gemini CLI / Cursor / other)
- MCP Firebird version / commit:
- OS:

**To reproduce**
Steps, the tool call, and the SQL/database involved.

**Relevant log excerpt**
From `bin/logs/` (never paste real credentials).

**Expected vs actual**
```

- [ ] **Step 2: Write feature_request.md**

```markdown
---
name: Feature request
about: Suggest an idea for MCP Firebird
labels: enhancement
---

**Problem**
What are you trying to do that the server doesn't support today?

**Proposed solution**
The tool/behavior you'd like.

**Alternatives considered**

**Additional context**
Which Firebird versions this should target, if relevant.
```

- [ ] **Step 3: Write PULL_REQUEST_TEMPLATE.md**

```markdown
## What & why

<!-- Describe the change and the motivation. -->

## Checklist

- [ ] Core suite / relevant tests pass locally (`pwsh tests/run_all.ps1` or a targeted run)
- [ ] `pwsh tests/check_core_boundary.ps1` passes (no `MVCFramework.*` in `sources/`)
- [ ] `pwsh scripts/check_spdx.ps1` passes (SPDX header on new production sources)
- [ ] No stdout pollution (logging goes to `bin/logs/`)
- [ ] Docs updated (README / CLAUDE.md / docs) if behavior changed
- [ ] Conventional Commit messages
```

- [ ] **Step 4: Write ci.yml**

```yaml
name: CI
on:
  push:
    branches: [ main, master ]
  pull_request:

jobs:
  hygiene:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: SPDX headers present
        shell: pwsh
        run: ./scripts/check_spdx.ps1

      - name: Core boundary (no MVCFramework in sources/)
        shell: pwsh
        run: |
          $bad = Select-String -Path 'sources/*.pas' -Pattern 'MVCFramework' -SimpleMatch
          if ($bad) { $bad | ForEach-Object { Write-Host "$($_.Path): $($_.Line)" }; throw 'Core boundary violated' }
          Write-Host 'Core boundary OK'

      - name: No committed .env (only .env.example)
        shell: bash
        run: |
          if git ls-files | grep -E '(^|/)\.env$'; then
            echo "A real .env is committed — remove it."; exit 1
          fi
          echo "No committed .env."
```

- [ ] **Step 5: Verify CI file is valid YAML and scripts referenced exist**

Run: `python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('yaml ok')"` (skip if PyYAML absent) and `test -f scripts/check_spdx.ps1 && echo scripts-ok`
Expected: `yaml ok` (or skipped) and `scripts-ok`.

- [ ] **Step 6: Verify the CI hygiene steps actually pass locally**

Run: `pwsh scripts/check_spdx.ps1` and the boundary snippet from Step 4 (run the three inline lines in `pwsh`).
Expected: "SPDX OK…" and "Core boundary OK".

- [ ] **Step 7: Commit**

```bash
git add .github
git commit -m "ci: add issue/PR templates and hygiene workflow (SPDX + boundary + secret scan)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: CHANGELOG + scratch-file cleanup

**Files:**
- Create: `CHANGELOG.md`
- Delete: `docs/Gemini_Generated_Image_roat5croat5croat.png` (and any other `docs/Gemini_Generated_Image_*.png`)

**Interfaces:**
- Consumes: nothing.

- [ ] **Step 1: Write CHANGELOG.md**

```markdown
# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-07-08

First public release.

### Added
- MCP server for Firebird 2.5–5.0 over stdio (JSON-RPC 2.0, protocol `2025-03-26`), built with
  [mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi).
- Tools: `fb_info`, `fb_list_tables`, `fb_describe_table`, `fb_generate_documentation`,
  `fb_analyze_query`, `fb_suggest_indexes`, `fb_suggest_index_drops`, `fb_audit_table`,
  `fb_evaluate_goal`, `fb_monitor_transactions`.
- `optimization_goal` and `health_check` prompts; `firebird://schema` resource.
- Runtime capability detection across engine versions; access-plan analysis; index add/drop
  advice; schema-health audit; transaction/sweep monitoring.
- Read-only by default (DDL/write gated behind `firebird.allow_ddl`).
- `--env <dir>` configuration, per-invocation tool tracing to the log.

### Notes
- Source-only release; requires Delphi 13 Athens to build.
```

- [ ] **Step 2: Delete the generator scratch file(s)**

```bash
git rm --ignore-unmatch docs/Gemini_Generated_Image_*.png 2>/dev/null || rm -f docs/Gemini_Generated_Image_*.png
```

- [ ] **Step 3: Verify no scratch images and no build artifacts staged**

Run: `ls docs/Gemini_Generated_Image_*.png 2>/dev/null; git status --short`
Expected: no `Gemini_Generated_Image` files listed; `git status` shows only intended files (CHANGELOG.md added, the png removed).

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git add -A docs
git commit -m "docs: add CHANGELOG 0.1.0; drop logo generator scratch file

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: Final release-readiness sweep

**Files:** none (verification only)

- [ ] **Step 1: Confirm the full release inventory exists**

Run:
```bash
for f in LICENSE NOTICE CHANGELOG.md CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md \
         AGENTS.md .github/workflows/ci.yml .github/PULL_REQUEST_TEMPLATE.md \
         .github/ISSUE_TEMPLATE/bug_report.md .github/ISSUE_TEMPLATE/feature_request.md \
         scripts/check_spdx.ps1 docs/logo.png docs/logo-icon-dark.png docs/logo-icon-light.png; do
  test -f "$f" && echo "ok  $f" || echo "MISSING  $f"; done
```
Expected: every line `ok`.

- [ ] **Step 2: Re-run hygiene checks**

Run: `pwsh scripts/check_spdx.ps1 && pwsh tests/check_core_boundary.ps1`
Expected: both pass.

- [ ] **Step 3: Confirm no secrets / artifacts committed**

Run: `git ls-files | grep -E '(^|/)\.env$|\.exe$|\.dll$|Gemini_Generated' || echo "clean"`
Expected: `clean`.

- [ ] **Step 4: Confirm no unintended tags/pushes happened**

Run: `git log --oneline -12 && git tag`
Expected: the release-prep commits present; **no `v0.1.0` tag** (the maintainer creates it manually).

- [ ] **Step 5: Report**

Summarize to the user: files added, that hygiene checks pass, and the remaining **manual** steps they perform: create annotated tag `v0.1.0`, `git push` + push tag, and cut the GitHub Release. Do not perform these.

---

## Self-Review notes

- **Spec coverage:** §1 Legal → Task 1+2; §2 Showcase → Task 4; §3 AGENTS.md → Task 3; §4 Community → Task 6+7; §5 CI → Task 7; §6 README/CHANGELOG → Task 4/5/8; §7 Logo → assets exist, cleanup in Task 8. README License badge/section → Task 4/5. All covered.
- **No push/tag:** enforced in Global Constraints and verified in Task 9 Step 4.
- **Boundary script portability:** flagged in Task 7; CI uses an inline relative-path check, not the hardcoded-path script.
- **SPDX scope:** production sources only, verified it does not touch `tests/**` (checker globs exclude tests).
```
