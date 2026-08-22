**[English](README.md) · [Italiano](README-IT.md) · [Español](README-ES.md) · [Deutsch](README-DE.md)**

<p align="center">
  <img src="https://raw.githubusercontent.com/danieleteti/mcp-firebird/master/docs/logo.png" alt="MCP Firebird" width="360">
</p>

<p align="center">
  <a href="https://github.com/danieleteti/mcp-firebird/blob/master/LICENSE"><img alt="License: PolyForm Internal Use 1.0.0" src="https://img.shields.io/badge/License-PolyForm_Internal_Use-blue.svg"></a>
  <img alt="MCP protocol 2025-03-26" src="https://img.shields.io/badge/MCP-2025--03--26-brightgreen.svg">
  <a href="https://github.com/danieleteti/mcp-server-delphi"><img alt="powered by mcp-server-delphi" src="https://img.shields.io/badge/powered%20by-mcp--server--delphi-orange.svg"></a>
  <a href="https://github.com/danieleteti/mcp-firebird/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/danieleteti/mcp-firebird/actions/workflows/ci.yml/badge.svg"></a>
</p>

# MCP Firebird

**Ask your AI assistant why a query is slow, and get an answer worth acting on.**

A [Model Context Protocol](https://modelcontextprotocol.io) server for **Firebird 2.5 to 5.0**.
Point it at a database and your assistant can read the real access plans, tell you which index is
missing and which four are dead weight, audit a table's health, and find the transaction that has
been holding garbage collection back since Tuesday.

The answers come out of *your* database, not out of an article: the server asks Firebird for the
plan (`SET PLANONLY`), reads the monitoring tables (`MON$`), and counts how many distinct values a
column really holds before claiming an index on it would pay off. Every answer arrives as
**Finding** (what is wrong), **SQL** (the statement that fixes it) and **Verify** (how to check it
worked). Nothing is written to your database: the server attaches read-only, and the SQL it hands
you is yours to run, if and when you decide to.

- **Transport:** stdio (JSON-RPC 2.0, MCP `2025-03-26`) · **Server identity:** `mcp-firebird` v`0.5.0`
- **Engines:** Firebird 2.5, 3.0, 4.0, 5.0 — capability-detected at runtime
- **Free** on your own databases, at any scale, no key and no expiry. A licence is needed only to
  pass the software on to somebody else ([details](https://github.com/danieleteti/mcp-firebird/blob/master/docs/editions.md))

---

## Quickstart

Five minutes, four steps. Windows x64.

**1. Get the server.** Download the [latest release](https://github.com/danieleteti/mcp-firebird/releases)
and unzip it, say into `C:\Tools\MCPFirebird`.
Building from source instead: [Building & testing](https://github.com/danieleteti/mcp-firebird/blob/master/docs/development.md).  <!-- release:drop -->

**2. Tell it which database.** Copy `.env.example` next to the exe as `.env` and fill in four lines:

```ini
firebird.database=C:\data\MYAPP.FDB
firebird.user=SYSDBA
firebird.password=masterkey
firebird.client_lib=C:\Program Files\Firebird\Firebird_5_0\fbclient.dll
```

The zip deliberately ships no `fbclient.dll`: the right one is your own server's client library.

**3. Register it with your AI agent.** It is a stdio server — the agent starts the exe itself, so
the whole installation is one command. Claude Code:

```powershell
claude mcp add firebird -- "C:\Tools\MCPFirebird\MCPFirebird.exe"
```

Claude Desktop (`%APPDATA%\Claude\claude_desktop_config.json`), Cursor (`.cursor/mcp.json`),
VS Code (`.vscode/mcp.json`) all take the same shape:

```json
{ "mcpServers": { "firebird": { "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe" } } }
```

Gemini CLI and OpenCode differ slightly — snippets for every client are in
[Setup](https://github.com/danieleteti/mcp-firebird/blob/master/docs/setup.md#install-it-into-your-ai-agent-claude-gemini-cursor-).

**4. Ask it something.**

> **You:** What Firebird version am I connected to, and which tables are in the database?
>
> **You:** This query is slow, why? `SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'`
>
> **You:** Suggest an index that fixes it.

That is the whole setup. If the client lists the server but shows no tools, see
**Troubleshooting**, at the bottom of this page.

---

## What you can ask it

| Ask | What happens |
|---|---|
| *"Document the CUSTOMERS table"* | Markdown docs: columns, PK, indexes, triggers. Leave the table out and you get the whole database, procedures and packages included |
| *"Why is this query slow?"* | The access plan, the NATURAL scans and external sorts in it, the engine's explained plan on 3.0+, **and** what the query really cost when executed once |
| *"Suggest an index"* | The cheapest remedy that explains the plan — refresh stale statistics, wake an inactive index, or create one — and **"no index, the scan is right here"** with the numbers, when that is the answer |
| *"Which indexes can I drop?"* | Duplicates, redundant prefixes, inactive and low-selectivity indexes, with the `DROP INDEX` and a verify step |
| *"Audit this table"* | Missing primary key, over-indexing, stale statistics |
| *"Keep optimizing until this query stops scanning NATURAL"* | The goal loop: it changes, re-measures on the database, and stops when the measurement says the goal is met — not when the assistant thinks so |
| *"It crawls every afternoon and nobody changed anything"* | Classifies the symptom before touching a tool, then samples `MON$` across a window to show what accumulates |
| *"Who is connected, and what are they running?"* | Every attachment with its user, address and process, the statement it is running now, and how long it has been running it |
| *"Back the database up"* | Runs `gbak` in the background and **restores what it wrote into a scratch database**, so the answer is "this backup restores", not "a file exists" |

Every analysis also closes with **what it does not rule out**: a plan cannot see contention, and a
snapshot cannot see accumulation.

**[→ Worked examples, verbatim tool output, a full round-trip on `employee.fdb`](https://github.com/danieleteti/mcp-firebird/blob/master/docs/usage.md)**

---

## The tools

Thirteen tools, three prompts, one resource. Full reference — arguments, what each one decides, the
raw `tools/call` shapes — in **[docs/tools.md](https://github.com/danieleteti/mcp-firebird/blob/master/docs/tools.md)**.

`fb_info` · `fb_list_tables` · `fb_generate_documentation` · `fb_analyze_query` ·
`fb_suggest_indexes` · `fb_suggest_index_drops` · `fb_audit_table` · `fb_evaluate_goal` ·
`fb_monitor_transactions` · `fb_sample_activity` · `fb_monitor_attachments` ·
`fb_backup_start` · `fb_backup_status`

`fb_backup_start` returns before the backup does — poll `fb_backup_status`. It needs
`firebird.backup_dir` set in the `.env`, `gbak.exe` beside your `fbclient.dll`, and room on that
disk for a second copy of the database while the verification restore runs.

Prompts: `optimization_goal` (iterate until met) · `health_check` · `classify_problem`.
Resource: `firebird://schema`.

Nine further tools appear in `tools/list` and belong to the [Enterprise edition](https://github.com/danieleteti/mcp-firebird/blob/master/docs/editions.md#enterprise-edition):
your assistant can see them and say what it would do with them.

---

## Editions

**Using it on your own databases is free, and stays free.** No trial, no expiry, no licence key,
no seat count. Consultants: it is your tool, use it on your clients' databases and charge for your
time. The one thing that needs a licence is **letting a copy out of your hands** — redistributing
it, embedding it in a product you sell, or offering it as a service.

A separate paid **Enterprise edition** picks up where an SQL connection ends: `firebird.conf`, the
machine's RAM and CPUs, `firebird.log`, the Trace API, the physical storage report. You want it
when the schema is in order and the database is still slow.

**[→ Editions, licensing, and the worked cases](https://github.com/danieleteti/mcp-firebird/blob/master/docs/editions.md)** · d.teti@bittime.it

---

## Documentation

| | |
|---|---|
| [Setup](https://github.com/danieleteti/mcp-firebird/blob/master/docs/setup.md) | Prerequisites, the `.env` reference, `--env <dir>`, several databases from one build, per-client snippets, manual smoke test |
| [Worked examples](https://github.com/danieleteti/mcp-firebird/blob/master/docs/usage.md) | The conversations, verbatim tool output, an optimization round-trip |
| [Tool reference](https://github.com/danieleteti/mcp-firebird/blob/master/docs/tools.md) | All ten tools, how the index advisor decides, prompts, resources, Enterprise tools |
| [Editions & licensing](https://github.com/danieleteti/mcp-firebird/blob/master/docs/editions.md) | What is free, what needs a licence, what Enterprise adds |
| [Building & testing](https://github.com/danieleteti/mcp-firebird/blob/master/docs/development.md) | Delphi build, the 2.5→5.0 test matrix, how it uses mcp-server-delphi |  <!-- release:drop -->
| [Problem catalog](https://github.com/danieleteti/mcp-firebird/blob/master/docs/firebird-problem-catalog.md) | Every problem detected, the fixture that provokes it, the milestone |

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Client shows the server but **no tools** | `.env` missing or DB unreachable: the server starts but tools fail on connect. Test with the [manual smoke test](https://github.com/danieleteti/mcp-firebird/blob/master/docs/setup.md#run--verify-manually). |
| `Your user name and password are not defined` (SQLSTATE 28000) | Wrong credentials, or a Firebird zip-kit that ships without a usable `SYSDBA` (see [Building & testing](https://github.com/danieleteti/mcp-firebird/blob/master/docs/development.md)). |
| Analysis tools return empty / no NATURAL scan on a **remote** DB | Ensure `firebird.host` is the real host (the plan analyzer uses the configured host). |
| `fbclient.dll` not found / wrong bitness | Set `firebird.client_lib` to a **Win64** `fbclient.dll`; a 5.0 client works against 2.5-5.0. |
| stdout has non-JSON noise | Logging must go to file only: keep `logger.config.file=loggerpro.stdio.json`. |
| Port 3050 already in use by another Firebird | Use a distinct port (the test harness puts FB 2.5 on **3070** for this reason). |

---

## Safety & compatibility

- **Read-only, and not on the honour system.** The server opens its transactions read-only, so
  an INSERT, UPDATE, DELETE or DDL is refused by Firebird, not by a check of ours that could
  be wrong about what a statement does. It matters because three tools execute SQL that arrives
  as text from the caller — `fb_analyze_query` measures the SELECT it analyzes,
  `fb_suggest_indexes` measures the one it advises on, and `fb_evaluate_goal` times one. All
  three also refuse anything that is not a plain SELECT before running it, and refuse to execute
  a statement whose parameters nobody bound; the read-only transaction is what holds if a
  refusal is ever wrong. The SQL
  an advisory hands you is yours to run, when and if you decide to. Tools that apply a change
  themselves are planned, and when they arrive they will be off unless you turn them on.
- **Cross-version.** Capability detection adapts feature use (MON$ tables, explained plans,
  BOOLEAN, INT128, timezones, parallel workers) to the connected engine; validated on FB
  2.5 / 3.0 / 4.0 / 5.0.
- **Single configured database** per server instance (run multiple instances for multiple DBs).

---

## License

From **v0.2.0**, licensed under the
**[PolyForm Internal Use License 1.0.0](https://github.com/danieleteti/mcp-firebird/blob/master/LICENSE)**:
free on your own databases, at any scale, and a licence is needed only to pass the software on to
somebody else. **v0.1.0 and earlier were released under Apache-2.0, and stay that way** for everyone
who received them. See
[Editions & licensing](https://github.com/danieleteti/mcp-firebird/blob/master/docs/editions.md)
and [`NOTICE`](https://github.com/danieleteti/mcp-firebird/blob/master/NOTICE).

Built with **[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi)**, which in turn
stands on **[DelphiMVCFramework](https://github.com/danieleteti/delphimvcframework)**. This server is
a complete, real-world example of what you can build with them: if you are writing your own MCP
server in Delphi, start there.
