**[English](README.md) · [Italiano](README-IT.md) · [Español](README-ES.md) · [Deutsch](README-DE.md)**

<p align="center">
  <img src="docs/logo.png" alt="MCP Firebird" width="360">
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: PolyForm Internal Use 1.0.0" src="https://img.shields.io/badge/License-PolyForm_Internal_Use-blue.svg"></a>
  <img alt="MCP protocol 2025-03-26" src="https://img.shields.io/badge/MCP-2025--03--26-brightgreen.svg">
  <a href="https://github.com/danieleteti/mcp-server-delphi"><img alt="powered by mcp-server-delphi" src="https://img.shields.io/badge/powered%20by-mcp--server--delphi-orange.svg"></a>
  <a href="https://github.com/danieleteti/mcp-firebird/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/danieleteti/mcp-firebird/actions/workflows/ci.yml/badge.svg"></a>
</p>

# MCP Firebird

**Chiedi al tuo assistente AI perché una query è lenta, e ricevi una risposta che puoi mettere in
pratica.**

Un server [Model Context Protocol](https://modelcontextprotocol.io) per **Firebird da 2.5 a 5.0**,
scritto in Delphi sul driver ufficiale `fbclient`. Collegalo a un database e un assistente legge i
tuoi piani di accesso, ti dice quali indici mancano e quali sono da buttare, controlla lo stato di
salute di una tabella e individua le transazioni rimaste aperte che bloccano la garbage collection.

Puoi anche dargli un obiettivo (*"questa query non deve più fare scansioni NATURAL"*, *"deve
scendere sotto i 200 ms"*) e lasciarlo lavorare: applica una modifica, la rimisura sul database,
e se non basta ci riprova. A dire che l'obiettivo è raggiunto non è l'assistente, ma la misura.

Non sono consigli generici sugli indici, di quelli che trovi in un qualunque articolo: le risposte
escono dal *tuo* database. Il server si fa dare da Firebird il piano di esecuzione della query
(`SET PLANONLY`), interroga le tabelle di monitoraggio (`MON$`), conta quanti valori distinti ci
sono davvero in una colonna prima di dire che vale la pena indicizzarla.

Ogni risposta arriva in tre parti: **Finding**, cos'ha trovato e perché è un problema; **SQL**,
il comando da eseguire per risolverlo, già scritto; **Verify**, come controllare che abbia
funzionato davvero. Nessun tool scrive sul database: il server legge e basta, e l'`SQL` che
propone lo esegui tu, quando e se vuoi.

> Costruito con **[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi)**, che a sua
> volta poggia su **[DelphiMVCFramework](https://github.com/danieleteti/delphimvcframework)**.
> Questo server è un esempio completo, e reale, di cosa ci si può costruire.

- **Trasporto:** stdio (JSON-RPC 2.0, protocollo MCP `2025-03-26`)
- **Identità del server:** `mcp-firebird` v`0.1.0`
- **Motori supportati:** Firebird 2.5, 3.0, 4.0, 5.0 (funzionalità rilevate a runtime)
- **Innocuo per il database:** analisi in sola lettura; nessun tool esegue DDL o SQL di scrittura
- **Gratuito** sui tuoi database, a qualunque scala, senza chiave e senza scadenza. Serve una
  licenza solo se dai il software a qualcun altro: lo rivendi dentro un tuo prodotto, lo lasci
  installato dal cliente, lo esponi come servizio ([dettagli sulla licenza](#edizioni-e-licenze))
- **[Edizione Enterprise](#edizione-enterprise)**, venduta a parte: analizza il *server* Firebird,
  non solo il database. Legge `firebird.conf`, la RAM e le CPU della macchina, `firebird.log` e la
  Trace API. Ti serve quando lo schema è a posto e il database è lento lo stesso

---

## Indice

1. [Cosa fa](#cosa-fa)
2. [Edizioni e licenze](#edizioni-e-licenze)
3. [Edizione Enterprise](#edizione-enterprise)
4. [Come usa mcp-server-delphi](#come-usa-mcp-server-delphi)  <!-- release:drop -->
5. [Requisiti](#requisiti)
6. [Build](#build)  <!-- release:drop -->
7. [Configurazione (`.env`)](#configurazione-env)
8. [Avviarlo e verificarlo a mano](#avviarlo-e-verificarlo-a-mano)
9. [Installarlo nel tuo agente AI](#installarlo-nel-tuo-agente-ai-claude-gemini-cursor-): Claude Desktop · Claude Code · Gemini CLI · OpenCode · Cursor / VS Code · generico
10. [Usarlo da Claude](#usarlo-da-claude): esempi reali
11. [I tool in dettaglio](#i-tool-in-dettaglio)
12. [Test del progetto](#test-del-progetto)  <!-- release:drop -->
13. [Problemi frequenti](#problemi-frequenti)

---

## Cosa fa

### Tool (9 free, più i 5 Enterprise annunciati in `tools/list`)

| Tool | Argomenti | A cosa serve |
|---|---|---|
| `fb_info` | *(nessuno)* | Versione del motore e funzionalità rilevate (JSON) |
| `fb_list_tables` | *(nessuno)* | Elenca le tabelle utente |
| `fb_generate_documentation` | `table_name?` | Documentazione Markdown (colonne, PK, indici) di una tabella o dell'intero database |
| `fb_analyze_query` | `sql` | Analisi del piano di accesso: individua scansioni NATURAL e SORT esterni |
| `fb_suggest_indexes` | `sql` | Propone nuovi indici a partire dai predicati risolti con scansione NATURAL (DDL già pronto) |
| `fb_suggest_index_drops` | `table_name` | Segnala indici duplicati, con prefisso ridondante, inattivi o poco selettivi |
| `fb_audit_table` | `table_name` | Stato di salute dello schema: PK assente, troppi indici, statistiche vecchie |
| `fb_evaluate_goal` | `goal_type`, `target`, `threshold` | Verifica deterministica dell'obiettivo (è il motore del ciclo di ottimizzazione) |
| `fb_monitor_transactions` | `stale_minutes?` | Salute di transazioni e sweep: distanza fra OIT/OAT/Next, transazioni lunghe che bloccano (con il loro ultimo statement SQL) |

Ogni indicazione arriva con un **Finding**, l'**SQL** già pronto e una **Verify**.

### Prompt (2)

- **`optimization_goal`**: il ciclo guidato da un obiettivo. Lo fissi, l'assistente itera sui tool
  `fb_*` e richiama `fb_evaluate_goal` finché non ottiene `met: true`. Si ferma da solo dopo troppe
  iterazioni o se smette di fare progressi.
- **`health_check`**: esame guidato della salute dell'intero database.

### Risorse (1)

- **`firebird://schema`**: lo schema del database, live, come singola risorsa.

---

## Edizioni e licenze

In breve: **sui tuoi database è gratuito, e gratuito resta.** Nessuna prova a tempo, nessuna
scadenza, nessuna chiave, nessun conteggio di postazioni, nessun limite al numero di tabelle o di
database. Installalo, mettilo in produzione, usalo tutti i giorni. Non contatta nessun server.

L'unica cosa che non puoi fare è darlo a qualcun altro.

MCP Firebird è **source-available, non open source** nel senso che dà al termine la Open Source
Initiative. Dirlo chiaro conta più di un badge: dalla **v0.2.0** la licenza è la
[PolyForm Internal Use License 1.0.0](LICENSE). Le versioni fino alla **v0.1.0 sono uscite sotto
Apache-2.0, e sotto Apache-2.0 restano** per chi le ha ricevute: una licenza concessa non si
revoca, e qui nessuno fa finta del contrario.

### Cosa puoi fare, senza pagare nulla

- Usarlo su qualunque database: tuo, della tua azienda, del tuo cliente. Sviluppo, collaudo,
  produzione.
- Usarlo a qualunque scala. Cento tabelle o diecimila, un database o cinquanta.
- **Usarlo nel tuo lavoro di consulenza.** Diagnostica, ottimizza, verifica e assisti i database
  Firebird dei tuoi clienti, e fatti pagare il tempo che ci metti. È il tuo strumento: tienilo.
- Leggere il sorgente. Tutto quanto. Impararci sopra e usare quello che impari.
- Modificarlo. Correggi un bug, aggiungi un rilevatore, cambia un messaggio, ed esegui la tua build.
- Usarlo in un'azienda di qualsiasi dimensione, a scopo di lucro o no, senza costi e senza
  registrarti.

### Cosa richiede una licenza

Un'unica idea, in tre forme: **far uscire il software dalle tue mani.**

- **Ridistribuirlo.** Pubblicare un fork, caricare una build, masterizzarlo su un CD, spedire il
  binario a un cliente, lasciarlo installato sul server di un cliente a incarico finito.
- **Metterlo dentro un prodotto che vendi.** Nel tuo ERP, nel tuo installer, nella tua immagine
  Docker, nella tua appliance: sorgente o binario, modificato o no.
- **Offrirlo come servizio.** Esporlo dietro una API o un agente ospitato, raggiungibile da persone
  fuori dalla tua organizzazione.

Dove il software gira, e di chi è il database che esamina, sono affari tuoi. Dove finiscono le sue
copie sono affari nostri.

Se il tuo caso è fra questi, la licenza esiste, e costa poco rispetto a quello che ci stai
costruendo sopra. Scrivi a **d.teti@bittime.it**.

### Quando devi comprare una licenza: casi concreti

| La tua situazione | Serve la licenza? |
|---|---|
| Il tuo DBA lo lancia ogni mattina sul Firebird di produzione dell'azienda | **No.** |
| I quaranta sviluppatori del tuo team lo usano ognuno sulla propria macchina | **No.** Nessuna postazione da contare, nessuna registrazione. |
| Fai il consulente, e lo lanci dal tuo portatile sul database del cliente | **No.** È il tuo strumento e resta tuo. Fattura quello che vuoi. |
| Idem, ma sei seduto alla scrivania del cliente e giri sul suo server | **No.** Riportatelo via quando esci. |
| Vai via e lasci una copia installata sul server del cliente | **Sì.** Il software è uscito dalle tue mani. |
| Fai hosting, e lo lanci sui database che ospiti | **No.** |
| ...e ai clienti dai un pulsante che lo lancia per loro | **Sì.** Così lo stai offrendo come servizio. |
| Lo spedisci dentro il tuo ERP Delphi, per dare ai clienti il "tuning AI del database" | **Sì.** È dentro un prodotto che fornisci tu. |
| Pubblichi su GitHub un fork con le tue migliorie | **Sì.** Ma prima parlane con noi: preferiamo fare il merge. |
| Ci scrivi un articolo, ci tieni un talk, ci fai un corso universitario | **No.** Leggilo, citalo, insegnalo. |
| Sei rimasto alla `v0.1.0`, che avevi preso sotto Apache-2.0 | **No.** Per te quella versione resta Apache-2.0 per sempre. |

La regola dietro la tabella, se preferisci ragionare invece di consultare: **conta dove finisce il
software, mai cosa ci hai fatto.** Finché ogni copia di MCP Firebird resta nelle tue mani non devi
niente: né per la scala a cui lo usi, né per quanto ci guadagni, né per il database di chi hai
sotto le mani. Se una copia esce, allora dobbiamo parlarne.

Esiste anche una **[edizione Enterprise](#edizione-enterprise)** a pagamento. È un altro prodotto,
non una versione gratuita mutilata: tutto quello che leggi in questo README sta in quella gratuita.

---

## Edizione Enterprise

### Dove finisce l'edizione free

L'edizione free non è una demo, e non è la Enterprise a cui hanno tolto le parti buone. È un lavoro
intero, fatto bene: **costringe il database a rispondere di sé.**

Legge lo schema. Spiega i piani. Trova gli indici che mancano e quelli che avanzano. Vede la chiave
primaria che non c'è, le statistiche vecchie, la transazione rimasta aperta che tiene ferma la
garbage collection. Nella maggior parte dei database, nella maggior parte dei casi, il problema è
lì, e lì si risolve. C'è chi lo userà per anni senza aver bisogno di altro, e non gli chiederemo mai un
centesimo.

Poi un giorno il report ti dice la verità: *lo schema è a posto. Gli indici sono a posto. Nessuna
scansione NATURAL, nessun sort esterno, statistiche fresche.* E il database è lento lo stesso.

**Ecco la linea.** L'edizione free ha risposto alla sua domanda, onestamente e fino in fondo, e la
risposta è che il problema non sta nel database. Sta nella macchina sotto, e nessuna `SELECT` te lo
farà mai vedere: non perché il tool si trattenga, ma perché SQL non guarda fuori dal proprio
processo.

### Dove comincia l'edizione Enterprise

Sono 2 GB di page buffers su una macchina con 8 GB di RAM. È il `forced writes` spento due anni fa
per un carico batch e mai più riacceso. È `LockHashSlots` fermo al default del 2010 con
quattrocento connessioni addosso, un indice profondo quattro livelli, un bugcheck scritto in
`firebird.log` ogni martedì alle 03:00 che non legge nessuno.

L'edizione free si collega a Firebird come ci si collega la tua applicazione: una normale
connessione SQL, con i diritti di sempre. **La Enterprise chiede di più.** Si attacca al Services
Manager da amministratore (è così che ti riporta `firebird.log`, pilota la Trace API e legge il
report dello storage fisico) e legge la configurazione e l'hardware del server. Sono privilegi
diversi, è diverso quanto danno può fare se sbaglia, ed è diverso il discorso da fare a chi quel
server lo amministra. Da qui, un prodotto diverso.

E non si limita a dirti cosa non va. **Fa l'esperimento.** Prende una baseline sotto carico reale,
cambia un parametro e uno soltanto, misura di nuovo, confronta le distribuzioni (p95 e p99, mai la
media), poi tiene la modifica o la rimette com'era. Il numero non te lo vende nessuno: te lo dice
il database.

| | Free | Enterprise |
|---|---|---|
| Schema, documentazione, piani, indici da creare o da togliere, audit dello schema | ✅ | ✅ |
| Salute di transazioni e sweep (`MON$`) | ✅ | ✅ |
| `fb_analyze_config`: `firebird.conf` e `databases.conf`, letti per questo motore, questa architettura, questo carico | ❌ | ✅ |
| `fb_analyze_storage`: profondità degli indici, riempimento delle pagine, catene di versioni dei record, distribuzione delle pagine | ❌ | ✅ |
| `fb_parse_log`: `firebird.log`, ovvero errori, sweep, bugcheck, crash | ❌ | ✅ |
| `fb_capture_trace`: Trace API, ovvero il carico vero, e quanto costa davvero | ❌ | ✅ |
| `fb_analyze_host`: RAM contro page buffers, CPU contro worker paralleli, tipo di storage | ❌ | ✅ |
| Baseline, distribuzioni, confronto prima/dopo: l'esperimento | ❌ | ✅ |

Guarda cosa *non* c'è in quella tabella: per costruire la versione a pagamento non è stato tolto
niente da quella gratuita. Ogni tool free resta free, e quelli ancora da scrivere resteranno dalla
parte del confine a cui appartengono. Il confine non è un paywall tirato dentro un elenco di
funzionalità: è la differenza fra interrogare un database e amministrare un server, e l'edizione
free è sempre stata da una parte sola.

Il difficile non è mai stato leggere `firebird.conf`: un file INI lo legge chiunque. E il valore
giusto di `LockHashSlots` non te lo può dare nessuno, onestamente: **la documentazione di Firebird
non ne indica uno ottimale**, e nemmeno per la page cache o per la sort cache. Quello che ti dà
l'esperienza è capire *quale* parametro chiama in causa il tuo sintomo: il throughput che crolla
sotto concorrenza mentre la CPU resta tranquilla punta alla lock table, mai alla page cache. La
mappa è il prodotto. Il valore in fondo alla mappa non viene affermato: viene misurato, sul tuo
database, sotto il tuo carico.

Quando ti serve lo capisci da solo, perché te lo avrà detto l'edizione free.

I cinque tool qui sopra compaiono già in `tools/list` nell'edizione free: il tuo assistente li vede
e sa dirti cosa ci farebbe. Se ne chiami uno, ti spiega come averlo.

**Licenze Enterprise, licenze commerciali e contratti di supporto:** d.teti@bittime.it


<!-- release:drop -->
## Come usa mcp-server-delphi

Ogni tool è un normale metodo Delphi con qualche attributo di
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi). Il framework fa il resto:
trasforma la classe in un tool provider MCP, ricava lo schema JSON-RPC dagli attributi e lo collega
al trasporto stdio. In questo repository non c'è una riga di codice di protocollo. Da
`providers/FirebirdToolsU.pas`:

```pascal
TFirebirdTools = class(TMCPToolProvider)
public
  [MCPTool('fb_info', 'Engine version, dialect, charset and detected capabilities of the configured Firebird database')]
  function FbInfo: TMCPToolResult;

  [MCPTool('fb_generate_documentation', 'Markdown documentation — columns, primary key, indexes — for one table, or for the whole database when table_name is empty')]
  function FbGenerateDocumentation([MCPParam('Table name; leave empty for the whole database', TMCPParamPresence.Optional)] const table_name: string): TMCPToolResult;

  [MCPTool('fb_analyze_query', 'Returns and analyzes the access plan of a SQL query (flags NATURAL scans and external sorts)')]
  function FbAnalyzeQuery([MCPParam('The SQL query to analyze')] const sql: string): TMCPToolResult;
end;
```

Prompt (`providers/FirebirdPromptsU.pas`) e risorse (`providers/FirebirdResourcesU.pas`) funzionano
allo stesso modo, sempre con gli attributi. Per l'elenco completo vedi il repository
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi).

---

## Requisiti

- **Windows x64**: il server è un'applicazione console Win64 nativa.
- Una **libreria client Firebird** (`fbclient.dll`) pari o più recente del server a cui ti colleghi.
  Un `fbclient.dll` 5.0 parla senza problemi con server dal 2.5 al 5.0.
- Un **database Firebird** raggiungibile.

Nel pacchetto non c'è nessun `fbclient.dll`, ed è voluto: quello giusto è quello del tuo server, e
un client disallineato è peggio che nessun client. Indicalo in `firebird.client_lib` (vedi sotto).

---

<!-- release:drop -->
## Build

Per compilare dai sorgenti servono in più **Delphi 13 Athens** (RAD Studio 37.0) con **FireDAC**,
**DMVCFramework** e la libreria **`mcp-server-delphi`**, entrambe presenti in locale. Per la matrice
di test servono gli zip-kit Firebird sotto `fb_versions/` e Python 3 con `pytest`.

Percorsi di ricerca che il progetto si aspetta (si impostano una volta in `app/MCPFirebird.dproj`):

```
C:\DEV\mcp-server-delphi\sources
<DMVCFramework>\sources   (every sources subfolder DMVC needs)
C:\DEV\mcp-firebird\sources
C:\DEV\mcp-firebird\providers
```

Compila l'app Win64 Debug dalla radice del repository:

```powershell
cmd /c _build_app.bat
```

`_build_app.bat` chiama `rsvars.bat` e poi `msbuild app\MCPFirebird.dproj /t:Clean;Build /p:Config=Debug /p:Platform=Win64`.
L'eseguibile finisce in **`bin\MCPFirebird.exe`**.

(Per il progetto di test DUnitX c'è il gemello `_build_core.bat`.)

---

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

---

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

---

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

Riavvia Claude Desktop. Nel client compaiono i tool `fb_*`, i prompt `optimization_goal` e
`health_check`, e la risorsa `firebird://schema`.

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

---

## Usarlo da Claude

Registrato il server, gli parli normalmente: sceglie lui il tool `fb_*` giusto, lo esegue sul
database che hai configurato, e ti restituisce SQL già pronto. Gli scambi qui sotto girano sul
database demo; al posto di tabelle e colonne metti le tue.

> In **Claude Desktop** i tool compaiono da soli e i due prompt li trovi fra i comandi (menu 🔌 /
> "+"). In **Claude Code** usa `/mcp` per ispezionare il server, e i prompt sono slash command. E
> puoi sempre forzargli la mano: *"usa i tool firebird"*.

### 1. Farsi un'idea

> **Tu:** A che versione di Firebird sono collegato, e cosa ho a disposizione?

Claude chiama **`fb_info`** e riporta versione del motore, dialetto, charset e funzionalità
rilevate (tabelle MON$, piani con explain, BOOLEAN, INT128, fusi orari, worker paralleli).

> **Tu:** Elencami le tabelle del database.

→ **`fb_list_tables`** → `CUSTOMERS`, `ORDERS`, `NOPK_LOG`, `OVERIDX`, `STALE_T`, …

### 2. Documentare uno schema

> **Tu:** Documenta la tabella CUSTOMERS.

→ **`fb_generate_documentation`** → colonne, la chiave primaria `CUSTOMER_ID` e gli indici.

> **Tu:** Genera la documentazione Markdown di tutto il database e mettila in un file.

→ ancora **`fb_generate_documentation`**, senza tabella: prende l'intero DB. Claude ti restituisce
il Markdown; se lo vuoi su disco chiedigli di salvarlo in `docs/schema.md`.

### 3. Capire perché una query è lenta, e sistemarla

> **Tu:** Questa query è lenta, perché?
> `SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'`

→ **`fb_analyze_query`** → *"⚠️ scansione NATURAL su CUSTOMERS: la colonna filtrata `CITY` non ha
un indice utile."*

> **Tu:** Suggeriscimi un indice che risolva.

→ **`fb_suggest_indexes`** → uno statement già pronto, e come verificarlo:

```sql
CREATE INDEX IDX_CUSTOMERS_CITY ON CUSTOMERS (CITY);
-- Verify: re-run fb_analyze_query; the NATURAL scan on CUSTOMERS should be gone.
```

> **Tu:** E questa? `SELECT * FROM CUSTOMERS ORDER BY CITY`

→ **`fb_analyze_query`** segnala un **SORT esterno**: per quell'ordinamento non c'è un indice
utilizzabile.

### 4. Fare pulizia fra gli indici

> **Tu:** Quali indici su ORDERS posso togliere tranquillamente?

→ **`fb_suggest_index_drops`** → segnala `IDX_ORDERS_CUSTOMER_DUP`, doppione dell'indice di sistema
della foreign key, con il `DROP INDEX` e il passo di verifica.

> **Tu:** Fai lo stesso su CUSTOMERS.

→ segnala il prefisso sinistro ridondante (`IDX_CUST_NAME`), l'indice inattivo (`IDX_CUST_CITY`) e
quello poco selettivo (`IDX_CUST_STATUS`).

### 5. Controllare la salute dello schema

> **Tu:** Fai l'audit della tabella NOPK_LOG.

→ **`fb_audit_table`** → *"🛑 critico. La tabella NOPK_LOG non ha PRIMARY KEY …"*, con l'
`ALTER TABLE … ADD CONSTRAINT` che rimedia. Su `OVERIDX` segnala che gli indici sono troppi; su
`STALE_T` che le statistiche sono vecchie, e ti dà il `SET STATISTICS INDEX …`.

> **Tu:** Fammi un health check completo del database.

→ Claude usa il prompt **`health_check`**: `fb_info` → `fb_list_tables` → `fb_suggest_index_drops`
su ogni tabella → un unico riepilogo per tabella, con tutto l'SQL già pronto.

### 6. Ottimizzare per obiettivo (finché non è raggiunto)

Il prompt **`optimization_goal`** manda Claude in un ciclo: misura, propone, rimisura, e si ferma
appena l'obiettivo è raggiunto, o quando non riesce più a migliorarlo.

> **Tu:** Usa il prompt optimization_goal. Continua a ottimizzare finché questa query non smette di
> fare una scansione NATURAL:
> `SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'`

Claude:
1. Chiama **`fb_evaluate_goal`** (`goal_type=query_no_natural_scan`) → `met: false`, è la baseline.
2. Chiama `fb_analyze_query` e `fb_suggest_indexes`, e ti presenta `CREATE INDEX IDX_CUSTOMERS_CITY …`.
3. L'SQL lo esegui tu, perché di base le scritture sono spente (vedi
   [Innocuo per il database](#innocuo-per-il-database-e-compatibile)).
4. Richiama `fb_evaluate_goal` → `met: true`, e si ferma lì.

L'obiettivo puoi anche darlo in numeri, per esempio *"portami questa query sotto i 50 ms"*
(`goal_type=query_time_ms`, `threshold=50`).

---

## Una sessione vera: ottimizzare una query su `employee.fdb`

Un giro completo sul database di esempio **`employee`** che Firebird si porta dietro
(`examples/empbuild/employee.fdb`). Gli output qui sotto sono i risultati veri dei tool.

> **Tu:** Analizza questa query Firebird e suggerisci come migliorarla:
> ```sql
> SELECT emp_no, first_name, last_name, salary
> FROM employee
> WHERE salary > 60000
> ```

**1. Baseline.** `fb_analyze_query` risponde (motore `3.0.12`):

```
PLAN (EMPLOYEE NATURAL)
```
> Scansione NATURAL su: EMPLOYEE. Lancia `fb_suggest_indexes` su questa query per avere il DDL già
> pronto.

`NATURAL` vuol dire che Firebird legge **tutte** le righe di `EMPLOYEE` e butta via quelle con
`salary <= 60000`: su `SALARY` non c'è un indice su cui fare seek.

**2. Conferma del problema.** `fb_evaluate_goal` (`goal_type=query_no_natural_scan`):

```json
{ "goal_type": "query_no_natural_scan", "measured": 1.0, "met": false,
  "iteration_hint": "plan: PLAN (EMPLOYEE NATURAL)", "engine_version": "3.0.12" }
```

**3. La soluzione.** `fb_suggest_indexes`:

```sql
CREATE INDEX IDX_EMPLOYEE_SALARY ON EMPLOYEE (salary);
```
> **Verify:** rilancia `fb_analyze_query`; il piano deve usare `IDX_EMPLOYEE_SALARY` e non mostrare
> più `EMPLOYEE NATURAL`. Poi esegui `SET STATISTICS INDEX IDX_EMPLOYEE_SALARY;` per aggiornare la
> selettività.

**4. Applicala** (il server è in sola lettura, il DDL lo lanci tu) e **rianalizza**: il piano
diventa `PLAN (EMPLOYEE INDEX (IDX_EMPLOYEE_SALARY))` e `fb_evaluate_goal` risponde `met: true`.

**Quando l'indice *non* va aggiunto.** Il guadagno c'è perché `salary > 60000` è **selettivo**:
poche righe. Se il predicato prendesse quasi tutta la tabella (`salary > 0`, per dire), il piano più
economico sarebbe proprio la scansione NATURAL, e l'indice aggiungerebbe solo peso in scrittura. Non
tutte le scansioni NATURAL sono un bug.

---

## I tool in dettaglio

Qualche esempio di chiamata (gli `arguments` di `tools/call` MCP):

```jsonc
// Describe a table (omit table_name for the whole database)
{ "name": "fb_generate_documentation", "arguments": { "table_name": "CUSTOMERS" } }

// Analyze a query's plan (flags NATURAL scans and external SORTs)
{ "name": "fb_analyze_query", "arguments": { "sql": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'" } }

// Suggest indexes for a slow query
{ "name": "fb_suggest_indexes", "arguments": { "sql": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'" } }

// Which indexes to drop on a table
{ "name": "fb_suggest_index_drops", "arguments": { "table_name": "ORDERS" } }

// Schema-health audit
{ "name": "fb_audit_table", "arguments": { "table_name": "NOPK_LOG" } }

// Goal check: "this query must no longer do a NATURAL scan"
{ "name": "fb_evaluate_goal",
  "arguments": { "goal_type": "query_no_natural_scan",
                 "target": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'",
                 "threshold": 0 } }
```

I `goal_type` che `fb_evaluate_goal` accetta in M1: `query_no_natural_scan`, `query_time_ms`,
`no_redundant_indexes`. In
[`docs/firebird-problem-catalog.md`](docs/firebird-problem-catalog.md) trovi ogni problema che i
tool sanno rilevare, la fixture che lo provoca e la milestone in cui arriva.

### I tool Enterprise

Questi cinque compaiono in `tools/list` anche qui, così il tuo assistente sa che esistono e sa
dirti cosa ci farebbe. Se li chiami in questa edizione rispondono con un `isError` che spiega come
averli. Sono implementati nell'[edizione Enterprise](#edizione-enterprise), che si attacca al
Services Manager da amministratore e legge configurazione e hardware del server: privilegi che
questa edizione non chiede mai.

| Tool | Argomenti | Cosa fa |
|---|---|---|
| `fb_analyze_config` | *(nessuno)* | Legge `firebird.conf` e `databases.conf` e passa in rassegna ogni impostazione che conta (page buffers, `TempCacheLimit`, `LockHashSlots`, `MaxUnflushedWrites`, `GCPolicy`, worker paralleli), misurandola su *questa* versione del motore e su *questa* architettura del server, visto che i default, e perfino l'esistenza di un parametro, cambiano con entrambe |
| `fb_analyze_storage` | `table_name?` | Il quadro fisico che nessuna `SELECT` ti fa vedere: profondità degli indici, riempimento delle pagine, lunghezza delle catene di versioni dei record, distribuzione delle pagine |
| `fb_parse_log` | *(nessuno)* | Ti riporta `firebird.log` via Services API e separa il rumore da quello che conta: bugcheck, pagine corrotte, errori di I/O, sweep che sono partiti, o che non sono mai partiti |
| `fb_capture_trace` | *(nessuno)* | Apre una sessione limitata di Trace API, campiona il carico vero e mette in fila gli statement che costano davvero, come distribuzione delle latenze e non come media |
| `fb_analyze_host` | `config_dir?` | Il motore contro il suo hardware: la RAM contro la memoria che la configurazione impegna davvero, i core contro `MaxParallelWorkers` e `CpuAffinityMask`, lo spazio libero contro la dimensione del database, e se le pagine che mancano costano un seek |

E poi la parte che ne fa un prodotto e non un referto: **baseline ed esperimenti.** Misuri sotto
carico vero, cambi un parametro, rimisuri, e ottieni un verdetto su quanto si è mossa la coda della
distribuzione, con il rollback se non si è mossa.

Per la maggior parte di questi parametri la documentazione di Firebird non indica un valore
ottimale, e non lo facciamo nemmeno noi. Quello che l'edizione Enterprise ti dà è la mappa che porta
dal sintomo al parametro che lo spiega, e il banco di prova che dimostra che la modifica ha
funzionato sul tuo database.

---

<!-- release:drop -->
## Test del progetto

La suite fa girare i **test core DUnitX contro server Firebird veri** (dal 2.5 al 5.0), più una
**suite di conformità stdio in Python** e un **controllo sul confine del core**.

### Cosa serve per la matrice di test

- Gli zip-kit Firebird sotto `fb_versions/` (percorsi e porte in `tests/fbkit.versions.psd1`).
  Porte: **2.5 → 3070**, 3.0 → 3053, 4.0 → 3054, 5.0 → 3055.
- **Una volta per kit:** gli zip-kit non hanno un `SYSDBA` utilizzabile. A server fermo, crealo in
  modalità embedded (serve per 3.0/4.0/5.0; il 2.5 funziona così com'è):
  ```
  <kit>\isql.exe -user SYSDBA "<kit>\security<N>.fdb"
    CREATE USER SYSDBA PASSWORD 'masterkey';
    COMMIT; QUIT;
  ```
  (`security3.fdb` / `security4.fdb` / `security5.fdb`).
- Python 3 con `pytest` (`python -m pip install pytest`).

### Far girare tutto (un comando)

```powershell
pwsh tests/run_all.ps1
```

#### Oppure con PyInvoke (`tasks.py`)

Un `tasks.py` incapsula build e test dall'inizio alla fine (`python -m pip install invoke`):

```powershell
invoke --list                 # show all tasks
invoke build                  # build the core test project + the MCP app
invoke core --version 5.0     # core suite against one FB version (start/seed/test/stop)
invoke matrix                 # core suite across every present FB version
invoke compliance             # Python stdio MCP compliance suite (on FB 5.0)
invoke boundary               # enforce the core/MVCFramework boundary
invoke all                    # full run_all.ps1 (matrix + boundary + compliance)
```

Per ogni kit presente: avvia il server, semina un `TESTDB.FDB` nuovo, lancia l'exe del core, ferma
il server. Poi esegue il controllo sul confine e la suite Python su 5.0. In coda ti aspetti:

```
==== Core suite on FB 2.5 ====   ... 27 passed / 3 ignored
==== Core suite on FB 3.0 ====   ... 27 passed / 3 ignored
==== Core suite on FB 4.0 ====   ... 27 passed / 3 ignored
==== Core suite on FB 5.0 ====   ... 27 passed / 3 ignored
Core boundary OK: no MVCFramework imports in sources/
7 passed
ALL SUITES PASSED
```

(I 3 test *ignored* sono rilevatori in attesa di M2: restano visibili come backlog.)

### Su una versione sola

```powershell
pwsh tests/fbkit.ps1   -Action start  -Version 5.0
pwsh tests/seed/make_seed.ps1          -Version 5.0
$env:FBTEST_PORT='3055'
$env:FBTEST_DB='C:\DEV\mcp-firebird\tests\seed\TESTDB.FDB'
$env:FBTEST_CLIENTLIB=(pwsh tests/fbkit.ps1 -Action client -Version 5.0)
& 'C:\DEV\mcp-firebird\tests\coreproject\MCPFirebirdCoreTests.exe'
pwsh tests/fbkit.ps1   -Action stop   -Version 5.0
```

### Solo la conformità Python

```powershell
pwsh tests/fbkit.ps1 -Action start -Version 5.0
pwsh tests/seed/make_seed.ps1 -Version 5.0
python -m pytest tests/test_mcp_firebird_stdio.py -v
pwsh tests/fbkit.ps1 -Action stop -Version 5.0
```

---

## Problemi frequenti

| Sintomo | Causa probabile e rimedio |
|---|---|
| Il client mostra il server ma **nessun tool** | `.env` che manca, o DB irraggiungibile: il server parte, ma i tool falliscono in connessione. Prova con lo [smoke test manuale](#avviarlo-e-verificarlo-a-mano). |
| `Your user name and password are not defined` (SQLSTATE 28000) | Credenziali sbagliate, o uno zip-kit senza `SYSDBA`: vedi sopra l'inizializzazione una tantum. |
| I tool di analisi non restituiscono niente, o nessuna scansione NATURAL, su un DB **remoto** | Controlla che `firebird.host` sia l'host vero: l'analizzatore dei piani usa l'host configurato. |
| `fbclient.dll` non trovato, o bitness sbagliata | Punta `firebird.client_lib` a un `fbclient.dll` **Win64**; un client 5.0 va bene dal 2.5 al 5.0. |
| Su stdout finisce roba che non è JSON | Il log deve andare solo su file: tieni `logger.config.file=loggerpro.stdio.json`. |
| Porta 3050 già occupata da un altro Firebird | Usane un'altra (è il motivo per cui l'harness di test mette FB 2.5 sulla **3070**). |

---

## Innocuo per il database, e compatibile

- **Sola lettura.** Nessun tool esegue DDL o SQL di scrittura. L'SQL che ti propone un'indicazione
  lo lanci tu, quando e se decidi di farlo. I tool che applicano da soli una modifica sono in
  programma: quando arriveranno, saranno spenti finché non li accendi tu.
- **Tutte le versioni.** Il rilevamento delle funzionalità adatta al motore connesso quello che il
  server usa (tabelle MON$, piani con explain, BOOLEAN, INT128, fusi orari, worker paralleli).
  Validato su FB 2.5 / 3.0 / 4.0 / 5.0.
- **Un solo database configurato** per istanza: se ti servono più DB, avvii più istanze.

---

## Licenza

Dalla **v0.2.0** la licenza è la **[PolyForm Internal Use License 1.0.0](LICENSE)**: gratuito sui
tuoi database, a qualunque scala, e la licenza serve solo per passare il software a qualcun altro.
Cosa vuol dire in pratica lo trovi in [Edizioni e licenze](#edizioni-e-licenze); vedi anche
[`NOTICE`](NOTICE).

**La v0.1.0 e le precedenti sono uscite sotto Apache-2.0, e sotto Apache-2.0 restano** per chi le ha
ricevute.

MCP Firebird è la vetrina di
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi). Se vuoi scriverti un server
MCP in Delphi, parti da lì.
