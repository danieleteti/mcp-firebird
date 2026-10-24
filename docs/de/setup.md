# Installation, Konfiguration, Registrierung

[← zurück zur README](../../README-DE.md)

Alles, was zum Laufen nötig ist: Voraussetzungen, die `.env`, die er liest, wie mehrere
Installationen auf mehrere Datenbanken zeigen, und der Snippet für jeden MCP-Client.

## Voraussetzungen

- **Windows x64** (der Server ist eine native Win64-Konsolenanwendung).
- Eine **Firebird-Client-Bibliothek** (`fbclient.dll`), passend zu deinem Zielserver oder neuer. Eine
  `fbclient.dll` aus 5.0 verbindet sich problemlos mit Servern von 2.5 bis 5.0.
- Eine erreichbare **Firebird-Datenbank**.

Der Download enthält absichtlich keine `fbclient.dll`: die richtige ist die deines Servers, und ein
unpassender Client ist schlimmer als gar keiner. Zeig mit `firebird.client_lib` darauf (siehe unten).

## Konfiguration (`.env`)

Standardmäßig liest der Server seine Konfiguration aus einer **`.env`-Datei im selben Ordner wie die
ausführbare Datei**. Wo dieser Ordner liegt, hängt davon ab, woher du die Exe hast:

| | Exe | Vorlage kopieren mit |
|---|---|---|
| heruntergeladenes Release | `MCPFirebird.exe` (der entpackte Ordner) | `Copy-Item .env.example .env` |
| selbst gebaut | `bin\MCPFirebird.exe` | `Copy-Item bin\.env.example bin\.env` |

Danach bearbeitest du sie. (`.env.example` beginnt mit einem Punkt: `ls` und der Explorer blenden sie
aus, solange du nicht ausdrücklich versteckte Dateien anzeigen lässt. Im ZIP ist sie enthalten.)

### Einen anderen Konfigurationsordner wählen: `--env <dir>`

Standardmäßig wird die `.env` aus dem Ordner der ausführbaren Datei gelesen. Mit **`--env <dir>`** liest
der Server sie stattdessen aus einem anderen Ordner. Das Argument ist ein **Verzeichnis** (der Ordner,
der die `.env` *enthält*), nicht die Datei selbst:

```powershell
MCPFirebird.exe --env C:\configs\prod      # reads C:\configs\prod\.env
MCPFirebird.exe --env=C:\configs\prod      # the --env=<dir> form also works
MCPFirebird.exe --env ..\shared            # relative paths resolve against the working directory
MCPFirebird.exe                            # no argument -> reads <exe folder>\.env
MCPFirebird.exe --env C:\configs\prod\.env # WRONG -> stops with an error (see below)
```

> **`--env` ist ein Ordner, niemals die `.env`-Datei.** Zeigst du damit auf die Datei (etwa
> `...\prod\.env`), verweigert der Server den Start und schreibt die Lösung nach stderr (MCP-Clients
> zeigen das in ihren Server-Logs an), statt stillschweigend mit leerer Konfiguration zu starten:
>
> ```
> MCPFirebird: --env must point at the FOLDER that contains the .env file, not at the file itself.
>   got:      C:\configs\prod\.env
>   use this: C:\configs\prod
> ```

**Wie das Argument beim Server ankommt.** MCP-Clients gehen nicht über eine Shell. Sie starten die
ausführbare Datei direkt, mit einem `command` und einem `args`-**Array**, in dem jedes Element zu genau
einem Argument wird. Um Shell-Quoting musst du dich also nicht kümmern (Pfade mit Leerzeichen sind kein
Problem), und das Verzeichnis schreibst du als eigenes Array-Element. Zwei gleichwertige Formen:

| Form | Wert von `args` |
|---|---|
| getrennt | `["--env", "C:\\configs\\prod"]` |
| zusammengefasst | `["--env=C:\\configs\\prod"]` |

**Zu Pfaden unter Windows:** in JSON müssen Backslashes **verdoppelt** werden
(`"C:\\configs\\prod"`); alternativ nimmst du Schrägstriche, die Windows akzeptiert und die kein
Escaping brauchen (`"C:/configs/prod"`). Verwende in MCP-Clients einen **absoluten** Pfad: das
Arbeitsverzeichnis, mit dem sie starten, ist unvorhersehbar, relative Pfade sind dort also
unzuverlässig. Jeder Start protokolliert den aufgelösten Ordner nach `logs\MCPFirebird.NN.mcp.log`:

```
Boot: .env directory "C:\configs\prod" (.env exists=True)
```

> **Hinweis:** Logs landen immer in einem Unterordner `logs\` neben der **ausführbaren Datei** (`logs\`
> direkt neben der Exe), unabhängig von `--env`.

#### `--env` aus den einzelnen MCP-Clients übergeben

**Claude Desktop** (`%APPDATA%\Claude\claude_desktop_config.json`), **Claude Code** (`.mcp.json`),
**Cursor** (`.cursor/mcp.json`) und **VS Code** (`.vscode/mcp.json`) verwenden alle dieselbe Form, ein
`command` plus ein `args`-Array:

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

Claude Code kann es auch über die CLI hinzufügen:

```powershell
claude mcp add firebird -- "C:\Tools\MCPFirebird\MCPFirebird.exe" --env "C:\configs\prod"
```

**Gemini CLI** (`~/.gemini/settings.json`), dieselbe `mcpServers`-Form:

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

**OpenCode** (`opencode.json`). Achtung, hier ist es anders: `command` ist ein **einziges Array**, das
die Argumente bereits enthält (ein eigenes `args`-Feld gibt es nicht):

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

#### Mehrere Datenbanken aus einem Build bedienen

Registriere **dieselbe ausführbare Datei** mehrfach, mit verschiedenen `--env`-Ordnern. Jeder Ordner
hat seine eigene `.env`:

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

Der Client zeigt dann zwei unabhängige Server (`firebird-prod`, `firebird-test`), jeder mit seiner
eigenen Datenbank verbunden.

| Key | Standard | Bedeutung |
|---|---|---|
| `firebird.host` | `localhost` | Server-Host (TCP). Für entfernte DBs den echten Host bzw. die IP eintragen |
| `firebird.port` | `3050` | Server-Port |
| `firebird.database` | *(leer)* | Vollständiger Pfad (oder Alias) der Datenbank auf dem Server |
| `firebird.user` | (erforderlich) | Benutzer für die Anmeldung |
| `firebird.password` | (erforderlich) | Passwort für die Anmeldung |
| `firebird.charset` | `UTF8` | Zeichensatz der Verbindung |
| `firebird.client_lib` | *(leer)* | Vollständiger Pfad zur `fbclient.dll`, die geladen werden soll |
| `logger.config.file` | `loggerpro.stdio.json` | Konfiguration des Datei-Loggers (Logs gehen nur in Dateien; stdout bleibt reines JSON-RPC) |

Beispiel für eine `.env`:

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

> **Warum eine Datei und keine vom Client übergebenen Umgebungsvariablen?** Die dotEnv-Strategie lautet
> *erst Datei, dann Umgebung*: die `.env`-Datei hat Vorrang, die Umgebungsvariablen des Betriebssystems
> sind der Rückfall. Die Konfiguration über `.env` verhält sich in jedem MCP-Client gleich, weil sie
> relativ zur `.exe` gelesen wird, ganz unabhängig vom Arbeitsverzeichnis des Clients. Halte diese Datei
> aus der Versionskontrolle heraus (sie steht bereits in `.gitignore`): sie enthält Zugangsdaten.

## Manuell starten & prüfen

Der Server spricht JSON-RPC über stdin/stdout. Du kannst ihn ohne jeden MCP-Client testen, indem du ihm
zeilenweise gerahmtes JSON hineinpipest. Aus PowerShell:

```powershell
$msgs = @(
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"manual","version":"1"}}}'
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"fb_info","arguments":{}}}'
) -join "`n"
$msgs | & .\MCPFirebird.exe
```

Erwartet wird: ein `initialize`-Ergebnis, das `mcp-firebird` nennt, ein `tools/list` mit den 10
`fb_*`-Tools und ein `fb_info` mit der tatsächlichen `engine_version`. (Die Logs liegen unter `logs\`,
stdout ist reines JSON-RPC.)

## In deinen KI-Agenten einbauen (Claude, Gemini, Cursor, …)

So kommt der Server vor einen KI-Agenten: du **registrierst ihn** in dessen Konfiguration, und von da
an kann der Agent während der Antwort seine Tools aufrufen. Nichts läuft als Dienst, nichts lauscht an
einem Port. Der Agent **startet die ausführbare Datei selbst**, als Kindprozess, und spricht mit ihr
über stdin/stdout (MCP nennt das einen *stdio-Server*). Schließt du den Agenten, ist der Server mit
verschwunden.

Die ganze Installation besteht also darin, dem Agenten **einen Befehl** zu nennen (den absoluten Pfad
zu `MCPFirebird.exe`), in der Datei oder der CLI, die sein Hersteller dafür vorsieht. Es folgen Rezepte
für die gängigen Agenten; alle sind derselbe Befehl in anderer Syntax. Die Datenbankverbindung gehört
nicht dazu: die liest der Server aus der `.env` neben der ausführbaren Datei (siehe oben) oder aus
`--env <dir>`.

### Claude Desktop

Bearbeite `%APPDATA%\Claude\claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe"
    }
  }
}
```

Starte Claude Desktop neu. Die `fb_*`-Tools, die Prompts `optimization_goal`, `health_check` und `classify_problem` sowie
die Ressource `firebird://schema` erscheinen im Client.

### Claude Code (CLI)

Mit einem Befehl hinzufügen (lokaler stdio-Server):

```powershell
claude mcp add firebird -- "C:\Tools\MCPFirebird\MCPFirebird.exe"
```

Oder committe eine projektweite `.mcp.json` im Wurzelverzeichnis des Repositorys, damit deine Kollegen
sie erben:

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

Prüfen mit `claude mcp list` (oder mit `/mcp` innerhalb einer Sitzung).

### Gemini CLI

Bearbeite `~/.gemini/settings.json` (oder eine projektbezogene `.gemini/settings.json`):

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

`/mcp` in der Gemini CLI listet danach den Server und seine Tools auf. Setzt du `cwd` auf den Ordner
der Exe, bleibt das Verzeichnis `logs\` aufgeräumt (die `.env` wird ohnehin über den Pfad der Exe
gefunden).

### OpenCode

Bearbeite `opencode.json` (global unter `~/.config/opencode/opencode.json` oder pro Projekt) und
registriere einen **lokalen** MCP-Server (`command` ist ein argv-Array):

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

Cursor liest `.cursor/mcp.json`, VS Code (und MCP-fähige Erweiterungen) lesen `.vscode/mcp.json`. Beide
verwenden dieselbe Form:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe"
    }
  }
}
```

### Jeder andere MCP-Client

Der Server ist ein gewöhnlicher **stdio**-MCP-Server. Egal welches Konfigurationsformat der Client hat,
gib ihm:

- **command:** `C:\Tools\MCPFirebird\MCPFirebird.exe`
- **args:** *(keine)*, oder `["--env", "C:\\configs\\prod"]`, um eine `.env` aus einem anderen Ordner zu verwenden
- **transport:** stdio
- **env:** *(nichts nötig)*, die Verbindung kommt aus der `.env`

> **Tipp:** Willst du verschiedene Clients auf verschiedene Datenbanken richten, gib jedem ein eigenes
> `--env <dir>` (einen Ordner mit eigener `.env`). Den ganzen Installationsordner zu kopieren ist
> unnötig. Beispiel für eine `.mcp.json` in Claude Code:
> ```json
> { "mcpServers": { "firebird": {
>     "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe",
>     "args": ["--env", "C:\\configs\\prod"] } } }
> ```
