# Installazione, configurazione, registrazione

[← torna al README](../../README-IT.md)

Tutto quello che serve per farlo partire: i requisiti, il `.env` che legge, come
puntare più installazioni su più database, e lo snippet esatto per ogni client MCP.

## Requisiti

- **Windows x64**: il server è un'applicazione console Win64 nativa.
- Una **libreria client Firebird** (`fbclient.dll`) pari o più recente del server a cui ti colleghi.
  Un `fbclient.dll` 5.0 parla senza problemi con server dal 2.5 al 5.0.
- Un **database Firebird** raggiungibile.

Nel pacchetto non c'è nessun `fbclient.dll`, ed è voluto: quello giusto è quello del tuo server, e
un client disallineato è peggio che nessun client. Indicalo in `firebird.client_lib` (vedi sotto).

## Configurazione (`.env`)

Di base il server legge la configurazione da un **file `.env` nella cartella dell'eseguibile**.
Quale sia quella cartella dipende da come ti sei procurato l'exe:

| | exe | copia il template con |
|---|---|---|
| release scaricata | `MCPFirebird.exe` (la cartella che hai scompattato) | `Copy-Item .env.example .env` |
| compilato dai sorgenti | `bin\MCPFirebird.exe` | `Copy-Item bin\.env.example bin\.env` |

Poi apri il file e modificalo. (`.env.example` comincia con un punto: `ls` ed Explorer non te lo
mostrano se non chiedi i file nascosti. Nello zip c'è.)

### Un'altra cartella di configurazione: `--env <dir>`

Senza argomenti il `.env` viene letto dalla cartella dell'eseguibile. Con **`--env <dir>`** lo leggi
da un'altra: l'argomento è una **directory**, cioè la cartella che *contiene* il `.env`, non il
file:

```powershell
MCPFirebird.exe --env C:\configs\prod      # reads C:\configs\prod\.env
MCPFirebird.exe --env=C:\configs\prod      # the --env=<dir> form also works
MCPFirebird.exe --env ..\shared            # relative paths resolve against the working directory
MCPFirebird.exe                            # no argument -> reads <exe folder>\.env
MCPFirebird.exe --env C:\configs\prod\.env # WRONG -> stops with an error (see below)
```

> **`--env` vuole una cartella, mai il file `.env`.** Se gli passi il file (ad esempio
> `...\prod\.env`) il server si rifiuta di partire e stampa su stderr come rimediare (i client MCP
> lo fanno vedere nei log del server), invece di avviarsi in silenzio con una configurazione vuota:
>
> ```
> MCPFirebird: --env must point at the FOLDER that contains the .env file, not at the file itself.
>   got:      C:\configs\prod\.env
>   use this: C:\configs\prod
> ```

**Come arriva l'argomento al server.** I client MCP non passano da una shell: lanciano direttamente
l'eseguibile con un `command` e un **array** `args`, dove ogni elemento è un argomento a sé. Quindi
il quoting non ti riguarda (i percorsi con spazi vanno benissimo) e la directory la scrivi come
elemento separato dell'array. Due forme equivalenti:

| Forma | valore di `args` |
|---|---|
| separata | `["--env", "C:\\configs\\prod"]` |
| unita | `["--env=C:\\configs\\prod"]` |

**Percorsi su Windows.** In JSON i backslash vanno **raddoppiati** (`"C:\\configs\\prod"`), oppure
usa gli slash normali, che Windows accetta e che non richiedono escape (`"C:/configs/prod"`). Nei
client MCP metti sempre un percorso **assoluto**: la working directory con cui ti lanciano è
imprevedibile, e i percorsi relativi lì non reggono. A ogni avvio la cartella risolta finisce in
`logs\MCPFirebird.NN.mcp.log`:

```
Boot: .env directory "C:\configs\prod" (.env exists=True)
```

> **Attenzione:** i log finiscono sempre nella sottocartella `logs\` accanto all'**eseguibile**,
> qualunque cosa dica `--env`.

#### Passare `--env` dai vari client MCP

**Claude Desktop** (`%APPDATA%\Claude\claude_desktop_config.json`), **Claude Code** (`.mcp.json`),
**Cursor** (`.cursor/mcp.json`) e **VS Code** (`.vscode/mcp.json`) usano tutti la stessa forma: un
`command` e un array `args`.

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

Claude Code lo aggiunge anche da riga di comando:

```powershell
claude mcp add firebird -- "C:\Tools\MCPFirebird\MCPFirebird.exe" --env "C:\configs\prod"
```

**Gemini CLI** (`~/.gemini/settings.json`). Stessa forma, stesso `mcpServers`:

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

**OpenCode** (`opencode.json`). Qui cambia una cosa: `command` è un **unico array** che contiene
già gli argomenti, e un campo `args` separato non esiste.

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

#### Più database con una sola build

Registra lo **stesso eseguibile** più volte, ognuna con una cartella `--env` diversa, e in ogni
cartella metti il suo `.env`:

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

Il client vede due server indipendenti (`firebird-prod`, `firebird-test`), ciascuno sul proprio
database.

| Chiave | Default | Significato |
|---|---|---|
| `firebird.host` | `localhost` | Host del server (TCP). Per un DB remoto metti l'host o l'IP vero |
| `firebird.port` | `3050` | Porta del server |
| `firebird.database` | *(vuoto)* | Percorso completo, o alias, del database sul server |
| `firebird.user` | `SYSDBA` | Utente |
| `firebird.password` | `masterkey` | Password |
| `firebird.charset` | `UTF8` | Set di caratteri della connessione |
| `firebird.client_lib` | *(vuoto)* | Percorso completo del `fbclient.dll` da caricare |
| `logger.config.file` | `loggerpro.stdio.json` | Configurazione del logger su file (i log vanno solo su file; su stdout passa solo JSON-RPC) |

Un `.env` di esempio:

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

> **Perché un file e non le variabili d'ambiente passate dal client?** La strategia dotEnv è
> *file-then-env*: prima il file `.env`, e solo come ripiego le variabili d'ambiente del sistema.
> Configurare con il `.env` funziona allo stesso modo su qualunque client MCP, perché il file viene
> cercato accanto all'`.exe` e la working directory del client non c'entra. Tienilo fuori dal
> controllo di versione (è già in `.gitignore`), visto che contiene credenziali.

## Avviarlo e verificarlo a mano

Il server parla JSON-RPC su stdin/stdout, quindi puoi provarlo senza nessun client MCP: gli mandi
qualche riga JSON e guardi cosa risponde. Da PowerShell:

```powershell
$msgs = @(
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"manual","version":"1"}}}'
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"fb_info","arguments":{}}}'
) -join "`n"
$msgs | & .\MCPFirebird.exe
```

Ti aspetti: un `initialize` che risponde `mcp-firebird`, un `tools/list` con i 10 tool `fb_*`, e
`fb_info` che restituisce la `engine_version` reale. (I log stanno sotto `logs\`; su stdout passa
solo JSON-RPC.)

## Installarlo nel tuo agente AI (Claude, Gemini, Cursor, …)

Il server arriva davanti a un agente AI così: lo **registri** nella configurazione dell'agente, e
da lì in poi l'agente può chiamarne i tool mentre ti risponde. Niente servizi, niente porte in
ascolto: è l'agente stesso ad **avviare l'eseguibile** come processo figlio e a parlargli su
stdin/stdout: in MCP si chiama *server stdio*. Chiudi l'agente e il server sparisce con lui.

Tutta l'installazione, quindi, è dire all'agente **un comando**: il percorso assoluto di
`MCPFirebird.exe`, nel file o nella CLI che il suo fornitore mette a disposizione. Qui sotto ci
sono le ricette per gli agenti più diffusi: è sempre lo stesso comando, in sintassi diverse. La
connessione al database non c'entra: quella il server la legge dal `.env` accanto all'eseguibile
(vedi sopra) o da `--env <dir>`.

### Claude Desktop

Modifica `%APPDATA%\Claude\claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe"
    }
  }
}
```

Riavvia Claude Desktop. Nel client compaiono i tool `fb_*`, i prompt `optimization_goal`,
`health_check` e `classify_problem`, e la risorsa `firebird://schema`.

### Claude Code (CLI)

Basta un comando (server stdio locale):

```powershell
claude mcp add firebird -- "C:\Tools\MCPFirebird\MCPFirebird.exe"
```

Oppure committa nella radice del repository un `.mcp.json` di progetto, così se lo ritrovano anche
i colleghi:

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

Controlla con `claude mcp list`, o con `/mcp` dentro una sessione.

### Gemini CLI

Modifica `~/.gemini/settings.json`, o un `.gemini/settings.json` di progetto:

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

Poi `/mcp` dentro Gemini CLI elenca il server e i suoi tool. Mettere `cwd` sulla cartella dell'exe
tiene in ordine la directory `logs\`; il `.env` lo trova comunque dal percorso dell'exe.

### OpenCode

Modifica `opencode.json` (globale in `~/.config/opencode/opencode.json`, o di progetto) e registra
un server MCP **local**: `command` è un array argv.

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

Cursor legge `.cursor/mcp.json`, VS Code (e le estensioni che parlano MCP) leggono
`.vscode/mcp.json`. La forma è la stessa:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe"
    }
  }
}
```

### Qualunque altro client MCP

È un normalissimo server MCP **stdio**. Qualunque sia il formato di configurazione, dagli questo:

- **command:** `C:\Tools\MCPFirebird\MCPFirebird.exe`
- **args:** *(nessuno)*, oppure `["--env", "C:\\configs\\prod"]` per leggere il `.env` da un'altra
  cartella
- **transport:** stdio
- **env:** *(niente)*, la connessione arriva dal `.env`

> **Suggerimento:** se vuoi client diversi su database diversi, dai a ognuno il suo `--env <dir>`,
> cioè una cartella con il proprio `.env`. Non serve duplicare l'installazione. Per esempio, in un
> `.mcp.json` di Claude Code:
> ```json
> { "mcpServers": { "firebird": {
>     "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe",
>     "args": ["--env", "C:\\configs\\prod"] } } }
> ```
