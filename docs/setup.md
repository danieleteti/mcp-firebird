# Setup: install, configure, register

[← back to the README](../README.md)

Everything about getting the server running: what it needs, the `.env` it reads, how to point
several installs at several databases, and the exact snippet for each MCP client.

## Prerequisites

- **Windows x64** (the server is a native Win64 console app).
- A **Firebird client library** (`fbclient.dll`) matching, or newer than, your target server.
  A 5.0 `fbclient.dll` connects fine to 2.5-5.0 servers.
- A reachable **Firebird database** to point at.

The download ships no `fbclient.dll` on purpose: the right one is your server's own, and a
mismatched client is worse than none. Point `firebird.client_lib` at it (see below).

---

## Configuration (`.env`)

By default the server reads its configuration from a **`.env` file in the same folder as the
executable**, so where that is depends on how you got the exe:

| | exe | copy the template with |
|---|---|---|
| downloaded release | `MCPFirebird.exe` (the folder you unzipped) | `Copy-Item .env.example .env` |
| built from source | `bin\MCPFirebird.exe` | `Copy-Item bin\.env.example bin\.env` |

Then edit it. (`.env.example` starts with a dot: `ls` and Explorer hide it unless you ask for
hidden files. It is in the zip.)

### Choosing a different config folder: `--env <dir>`

By default the `.env` is read from the executable's own folder. Pass **`--env <dir>`** to read it
from another folder instead. The argument is a **directory** (the folder that *contains* the
`.env`), not the file itself:

```powershell
MCPFirebird.exe --env C:\configs\prod      # reads C:\configs\prod\.env
MCPFirebird.exe --env=C:\configs\prod      # the --env=<dir> form also works
MCPFirebird.exe --env ..\shared            # relative paths resolve against the working directory
MCPFirebird.exe                            # no argument -> reads <exe folder>\.env
MCPFirebird.exe --env C:\configs\prod\.env # WRONG -> stops with an error (see below)
```

> **`--env` is a folder, never the `.env` file.** If you point it at the file (e.g.
> `...\prod\.env`) the server refuses to start and prints the fix on stderr (which MCP clients
> surface in their server logs) instead of silently starting with an empty config:
>
> ```
> MCPFirebird: --env must point at the FOLDER that contains the .env file, not at the file itself.
>   got:      C:\configs\prod\.env
>   use this: C:\configs\prod
> ```

**How the argument reaches the server.** MCP clients don't go through a shell. They spawn the
executable directly with a `command` plus an `args` **array**, where each array element becomes one
separate argument. So there is no shell quoting to worry about (paths with spaces are fine), and you
write the directory as its own array element. Two equivalent forms:

| Form | `args` value |
|---|---|
| separate | `["--env", "C:\\configs\\prod"]` |
| joined | `["--env=C:\\configs\\prod"]` |

**Path notes (Windows):** in JSON, backslashes must be **doubled** (`"C:\\configs\\prod"`), or use
forward slashes, which Windows accepts and don't need escaping (`"C:/configs/prod"`). Prefer an
**absolute** path in MCP clients: the working directory they launch with is unpredictable, so
relative paths are unreliable there. Every startup logs the resolved folder to
`logs\MCPFirebird.NN.mcp.log`:

```
Boot: .env directory "C:\configs\prod" (.env exists=True)
```

> **Note:** logs are always written to a `logs\` subfolder next to the **executable** (`logs\` beside the exe),
> regardless of `--env`.

#### Passing `--env` from each MCP client

**Claude Desktop** (`%APPDATA%\Claude\claude_desktop_config.json`), **Claude Code** (`.mcp.json`),
**Cursor** (`.cursor/mcp.json`) and **VS Code** (`.vscode/mcp.json`) all use the same shape, a
`command` plus an `args` array:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe",
      "args": ["--env", "C:\\configs\\prod"]
    }
  }
}
```

Claude Code can also add it from the CLI:

```powershell
claude mcp add firebird -- "C:\Tools\MCPFirebird\MCPFirebird.exe" --env "C:\configs\prod"
```

**Gemini CLI** (`~/.gemini/settings.json`), same `mcpServers` shape:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe",
      "args": ["--env", "C:\\configs\\prod"]
    }
  }
}
```

**OpenCode** (`opencode.json`). Note the difference: `command` is a **single array** that already
includes the arguments (there is no separate `args` field):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "firebird": {
      "type": "local",
      "command": ["C:\\Tools\\MCPFirebird\\MCPFirebird.exe", "--env", "C:\\configs\\prod"],
      "enabled": true
    }
  }
}
```

#### Serving several databases from one build

Register the **same executable** more than once with different `--env` folders. Each folder holds
its own `.env`:

```json
{
  "mcpServers": {
    "firebird-prod": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe",
      "args": ["--env", "C:\\configs\\prod"]
    },
    "firebird-test": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe",
      "args": ["--env", "C:\\configs\\test"]
    }
  }
}
```

```
C:\configs\prod\.env      <- production host/port/database
C:\configs\test\.env      <- test host/port/database
```

The client then shows two independent servers (`firebird-prod`, `firebird-test`), each connected to
its own database.

| Key | Default | Meaning |
|---|---|---|
| `firebird.host` | `localhost` | Server host (TCP). Use the real host/IP for remote DBs |
| `firebird.port` | `3050` | Server port |
| `firebird.database` | *(empty)* | Full path (or alias) of the database on the server |
| `firebird.user` | `SYSDBA` | Login user |
| `firebird.password` | `masterkey` | Login password |
| `firebird.charset` | `UTF8` | Connection character set |
| `firebird.client_lib` | *(empty)* | Full path to `fbclient.dll` to load |
| `firebird.backup_dir` | *(empty)* | Folder `fb_backup_database` may write backups into. Never accepted from the caller — required only when that tool runs |
| `logger.config.file` | `loggerpro.stdio.json` | File-logger config (logs go to file only; stdout stays pure JSON-RPC) |

Example `.env`:

```ini
firebird.host=localhost
firebird.port=3050
firebird.database=C:\data\MYAPP.FDB
firebird.user=SYSDBA
firebird.password=masterkey
firebird.charset=UTF8
firebird.client_lib=C:\Program Files\Firebird\Firebird_5_0\fbclient.dll
logger.config.file=loggerpro.stdio.json
```

> **Why a file and not client-passed env vars?** The dotEnv strategy is *file-then-env*: the
> `.env` file takes priority, OS environment variables are the fallback. Configuring via
> `.env` works identically across every MCP client because it is read relative to the
> `.exe`, regardless of the client's working directory. Keep this file out of version control
> (it is already `.gitignore`d): it holds credentials.

---

## Run & verify manually

The server speaks JSON-RPC over stdin/stdout. You can smoke-test it without any MCP client by
piping framed JSON lines into it. From PowerShell:

```powershell
$msgs = @(
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"manual","version":"1"}}}'
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"fb_info","arguments":{}}}'
) -join "`n"
$msgs | & .\MCPFirebird.exe
```

Expected: an `initialize` result naming `mcp-firebird`, a `tools/list` with the 10 `fb_*` tools,
and `fb_info` returning the live `engine_version`. (Logs appear under `logs\`; stdout is
pure JSON-RPC.)

---

## Install it into your AI agent (Claude, Gemini, Cursor, …)

This is how the server gets in front of an AI agent: you **register it** in the agent's
configuration, and from then on the agent can call its tools while answering you. Nothing runs as a
service and nothing listens on a port. The agent **starts the executable itself**, as a child
process, and talks to it over stdin/stdout (this is what MCP calls a *stdio server*). Close the
agent and the server is gone with it.

So the whole installation is: tell the agent **one command** (the absolute path to
`MCPFirebird.exe`) in the file or CLI its vendor gives you for the purpose. Recipes for the
common agents follow; all of them are the same command in different syntax. The database
connection is not part of it: the server reads that from the `.env` beside the executable (above),
or from `--env <dir>`.

### Claude Desktop

Edit `%APPDATA%\Claude\claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe"
    }
  }
}
```

Restart Claude Desktop. The `fb_*` tools, the `optimization_goal` / `health_check` / `classify_problem` prompts, and
the `firebird://schema` resource appear in the client.

### Claude Code (CLI)

Add it with one command (local stdio server):

```powershell
claude mcp add firebird -- "C:\Tools\MCPFirebird\MCPFirebird.exe"
```

Or commit a project-scoped `.mcp.json` at the repo root so teammates inherit it:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe",
      "args": [],
      "env": {}
    }
  }
}
```

Verify with `claude mcp list` (or `/mcp` inside a session).

### Gemini CLI

Edit `~/.gemini/settings.json` (or a project-level `.gemini/settings.json`):

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe",
      "args": [],
      "cwd": "C:\\Tools\\MCPFirebird",
      "timeout": 30000,
      "trust": false
    }
  }
}
```

Then `/mcp` inside Gemini CLI lists the server and its tools. Setting `cwd` to the exe's folder
keeps the `logs\` directory tidy (the `.env` is found via the exe path regardless).

### OpenCode

Edit `opencode.json` (global `~/.config/opencode/opencode.json` or per-project) and register a
**local** MCP server (`command` is an argv array):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "firebird": {
      "type": "local",
      "command": ["C:\\Tools\\MCPFirebird\\MCPFirebird.exe"],
      "enabled": true
    }
  }
}
```

### Cursor / VS Code

Cursor reads `.cursor/mcp.json`; VS Code (and MCP-aware extensions) read `.vscode/mcp.json`.
Both use the same shape:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe"
    }
  }
}
```

### Any other MCP client

The server is a standard **stdio** MCP server. Whatever the client's config format, give it:

- **command:** `C:\Tools\MCPFirebird\MCPFirebird.exe`
- **args:** *(none)*, or `["--env", "C:\\configs\\prod"]` to use a `.env` from another folder
- **transport:** stdio
- **env:** *(none required)*, connection comes from the `.env`

> **Tip:** to point different clients at different databases, give each one a different
> `--env <dir>` (a folder with its own `.env`). No need to copy the whole install folder. For
> example, in a Claude Code `.mcp.json`:
> ```json
> { "mcpServers": { "firebird": {
>     "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe",
>     "args": ["--env", "C:\\configs\\prod"] } } }
> ```
