**[English](README.md) · [Italiano](README-IT.md) · [Español](README-ES.md) · [Deutsch](README-DE.md)**

<p align="center">
  <img src="https://raw.githubusercontent.com/danieleteti/mcp-firebird/master/docs/logo.png" alt="MCP Firebird" width="360">
</p>

<p align="center">
  <a href="https://github.com/danieleteti/mcp-firebird/blob/master/LICENSE"><img alt="Licenza: PolyForm Internal Use 1.0.0" src="https://img.shields.io/badge/License-PolyForm_Internal_Use-blue.svg"></a>
  <img alt="Protocollo MCP 2025-03-26" src="https://img.shields.io/badge/MCP-2025--03--26-brightgreen.svg">
  <a href="https://github.com/danieleteti/mcp-server-delphi"><img alt="powered by mcp-server-delphi" src="https://img.shields.io/badge/powered%20by-mcp--server--delphi-orange.svg"></a>
  <a href="https://github.com/danieleteti/mcp-firebird/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/danieleteti/mcp-firebird/actions/workflows/ci.yml/badge.svg"></a>
</p>

# MCP Firebird

**Chiedi al tuo assistente AI perché una query è lenta, e ottieni una risposta su cui agire.**

Un server [Model Context Protocol](https://modelcontextprotocol.io) per **Firebird da 2.5 a 5.0**.
Puntalo su un database e il tuo assistente legge i piani di accesso veri, ti dice quale indice
manca e quali quattro sono peso morto, verifica la salute di una tabella e trova la transazione
che da martedì tiene ferma la garbage collection.

Le risposte escono dal *tuo* database, non da un articolo: il server chiede il piano a Firebird
(`SET PLANONLY`), legge le tabelle di monitoraggio (`MON$`), e conta quanti valori distinti ha
davvero una colonna prima di sostenere che indicizzarla convenga. Ogni risposta arriva come
**Finding** (cosa non va), **SQL** (lo statement che lo risolve) e **Verify** (come controllare che
abbia funzionato). Nel tuo database non viene scritto niente: il server si attacca in sola lettura,
e l'SQL che ti consegna lo esegui tu, se e quando decidi.

- **Trasporto:** stdio (JSON-RPC 2.0, MCP `2025-03-26`) · **Identità del server:** `mcp-firebird` v`0.6.0`
- **Motori:** Firebird 2.5, 3.0, 4.0, 5.0 — rilevati a runtime
- **Gratis** sui tuoi database, a qualsiasi scala, senza chiavi e senza scadenze. La licenza serve
  solo per far uscire il software dalle tue mani ([dettagli](https://github.com/danieleteti/mcp-firebird/blob/master/docs/it/editions.md))

---

## Partenza rapida

Cinque minuti, quattro passi. Windows x64.

**1. Prendi il server.** Scarica l'[ultima release](https://github.com/danieleteti/mcp-firebird/releases)
e scompattala, per esempio in `C:\Tools\MCPFirebird`.
Se preferisci compilarlo: [Build e test](https://github.com/danieleteti/mcp-firebird/blob/master/docs/it/development.md).  <!-- release:drop -->

**2. Digli qual è il database.** Copia `.env.example` accanto all'exe come `.env` e riempi quattro righe:

```ini
firebird.database=C:\data\MYAPP.FDB
firebird.user=SYSDBA
firebird.password=masterkey
firebird.client_lib=C:\Program Files\Firebird\Firebird_5_0\fbclient.dll
```

Lo zip non contiene nessun `fbclient.dll`, di proposito: quello giusto è la libreria client del tuo
server.

**3. Registralo nel tuo agente AI.** È un server stdio — l'exe lo avvia l'agente, quindi tutta
l'installazione è un comando. Claude Code:

```powershell
claude mcp add firebird -- "C:\Tools\MCPFirebird\MCPFirebird.exe"
```

Claude Desktop (`%APPDATA%\Claude\claude_desktop_config.json`), Cursor (`.cursor/mcp.json`) e
VS Code (`.vscode/mcp.json`) usano la stessa forma:

```json
{ "mcpServers": { "firebird": { "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe" } } }
```

Gemini CLI e OpenCode cambiano un po' — gli snippet per ogni client sono in
[Installazione](https://github.com/danieleteti/mcp-firebird/blob/master/docs/it/setup.md#installarlo-nel-tuo-agente-ai-claude-gemini-cursor-).

**4. Chiedigli qualcosa.**

> **Tu:** A che versione di Firebird sono collegato, e quali tabelle ci sono nel database?
>
> **Tu:** Questa query è lenta, perché? `SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'`
>
> **Tu:** Suggeriscimi un indice che la sistemi.

L'installazione è tutta qui. Se il client mostra il server ma nessun tool, vedi **Problemi
frequenti**, in fondo a questa pagina.

---

## Cosa puoi chiedergli

| Chiedi | Cosa succede |
|---|---|
| *"Documenta la tabella CUSTOMERS"* | Documentazione Markdown: colonne, PK, indici, trigger. Senza nome tabella ottieni tutto il database, procedure e package inclusi |
| *"Perché questa query è lenta?"* | Il piano di accesso, le scansioni NATURAL e i SORT esterni che contiene, il piano spiegato dal motore su 3.0+, **e** quanto è costata davvero eseguendola una volta |
| *"Suggeriscimi un indice"* | Il rimedio più economico che spiega il piano — rinfrescare statistiche vecchie, risvegliare un indice inattivo, o crearne uno — e **"nessun indice, qui la scansione è giusta"** con i numeri, quando è quella la risposta |
| *"Quali indici posso eliminare?"* | Duplicati, prefissi ridondanti, indici inattivi e a bassa selettività, con il `DROP INDEX` e il passo di verifica |
| *"Fai l'audit di questa tabella"* | Chiave primaria assente, troppi indici, statistiche vecchie |
| *"Continua a ottimizzare finché questa query non smette di fare NATURAL"* | Il ciclo a obiettivo: cambia, rimisura sul database, e si ferma quando lo dice la misura — non quando lo pensa l'assistente |
| *"Ogni pomeriggio rallenta e nessuno ha toccato niente"* | Classifica il sintomo prima di toccare un tool, poi campiona `MON$` su una finestra per mostrare cosa si accumula |
| *"Chi è collegato, e cosa sta eseguendo?"* | Ogni attachment con utente, indirizzo e processo, lo statement che sta eseguendo adesso e da quanto |
| *"Fammi vedere le righe che ci sono davvero"* | `fb_query` esegue la SELECT e restituisce le righe, con un tetto perché una risposta resti una risposta. Nient'altro passa: né UPDATE, né DELETE, né DDL |
| *"L'applicazione si collega come SYSDBA. Cosa dovrebbe usare?"* | `app_user_plan` chiede cosa fa davvero l'applicazione — poche domande, ognuna delle quali cambia gli statement — poi `fb_suggest_grants` li scrive dal catalogo: l'utenza, un ruolo, i grant, e il ruolo attivato nel modo che la tua versione richiede |
| *"Chi può leggere questa tabella?"* | Tutti i grant registrati nel database, e i tre che di solito sono errori: PUBLIC, `WITH GRANT OPTION`, e i ruoli di cui non è membro nessuno |
| *"Fammi il backup del database"* | Esegue `gbak` in background e **ripristina quello che ha scritto in un database usa-e-getta**: la risposta non è "esiste un file" ma "questo backup si ripristina" |

Ogni analisi chiude anche dichiarando **che cosa non ha escluso**: un piano non vede la contesa, e
uno snapshot non vede l'accumulo.

**[→ Esempi pratici, output verbatim dei tool, un giro completo su `employee.fdb`](https://github.com/danieleteti/mcp-firebird/blob/master/docs/it/usage.md)**

---

## I tool

Sedici tool, quattro prompt, una risorsa. Riferimento completo — argomenti, cosa decide ciascuno, le
chiamate `tools/call` grezze — in **[docs/it/tools.md](https://github.com/danieleteti/mcp-firebird/blob/master/docs/it/tools.md)**.

`fb_info` · `fb_list_tables` · `fb_generate_documentation` · `fb_query` · `fb_analyze_query` ·
`fb_suggest_indexes` · `fb_suggest_index_drops` · `fb_audit_table` · `fb_audit_security` ·
`fb_suggest_grants` · `fb_evaluate_goal` · `fb_monitor_transactions` · `fb_sample_activity` ·
`fb_monitor_attachments` · `fb_backup_start` · `fb_backup_status`

`fb_backup_start` torna prima del backup — poi fai polling con `fb_backup_status`. Gli serve
`firebird.backup_dir` nel `.env`, `gbak.exe` accanto al tuo `fbclient.dll`, e spazio su quel disco
per una seconda copia del database mentre gira il ripristino di verifica.

Prompt: `optimization_goal` (itera finché non è raggiunto) · `health_check` · `classify_problem` ·
`app_user_plan` (capire cosa deve poter fare un utente applicativo, e produrne l'SQL).
Risorsa: `firebird://schema`.

Altri nove tool compaiono in `tools/list` e appartengono all'[edizione Enterprise](https://github.com/danieleteti/mcp-firebird/blob/master/docs/it/editions.md#edizione-enterprise):
il tuo assistente li vede e sa dirti cosa ci farebbe.

---

## Edizioni

**Usarlo sui tuoi database è gratis, e resta gratis.** Nessuna prova, nessuna scadenza, nessuna
chiave, nessun conteggio di postazioni. Consulenti: è il vostro strumento, usatelo sui database dei
clienti e fatturate il vostro tempo. L'unica cosa che richiede una licenza è **far uscire una copia
dalle vostre mani** — ridistribuirlo, incorporarlo in un prodotto che vendete, o offrirlo come
servizio.

L'**edizione Enterprise**, a pagamento, riprende dove finisce una connessione SQL: `firebird.conf`,
la RAM e le CPU della macchina, `firebird.log`, la Trace API, il report dello storage fisico. Serve
quando lo schema è a posto e il database è ancora lento.

**[→ Edizioni, licenze e i casi concreti](https://github.com/danieleteti/mcp-firebird/blob/master/docs/it/editions.md)** · d.teti@bittime.it

---

## Documentazione

| | |
|---|---|
| [Installazione](https://github.com/danieleteti/mcp-firebird/blob/master/docs/it/setup.md) | Requisiti, riferimento del `.env`, `--env <dir>`, più database da una sola installazione, snippet per ogni client, prova manuale |
| [Esempi pratici](https://github.com/danieleteti/mcp-firebird/blob/master/docs/it/usage.md) | Le conversazioni, l'output verbatim dei tool, un giro completo di ottimizzazione |
| [I tool in dettaglio](https://github.com/danieleteti/mcp-firebird/blob/master/docs/it/tools.md) | Tutti e quindici i tool, come decide l'advisor degli indici, prompt, risorse, tool Enterprise |
| [Edizioni e licenze](https://github.com/danieleteti/mcp-firebird/blob/master/docs/it/editions.md) | Cosa è gratis, cosa richiede una licenza, cosa aggiunge Enterprise |
| [Build e test](https://github.com/danieleteti/mcp-firebird/blob/master/docs/it/development.md) | Build Delphi, la matrice di test 2.5→5.0, come usa mcp-server-delphi |  <!-- release:drop -->
| [Catalogo dei problemi](https://github.com/danieleteti/mcp-firebird/blob/master/docs/firebird-problem-catalog.md) | Ogni problema rilevato, la fixture che lo provoca, il milestone (in inglese) |

---

## Problemi frequenti

| Sintomo | Causa probabile e rimedio |
|---|---|
| Il client mostra il server ma **nessun tool** | `.env` che manca, o DB irraggiungibile: il server parte, ma i tool falliscono in connessione. Prova con lo [smoke test manuale](https://github.com/danieleteti/mcp-firebird/blob/master/docs/it/setup.md#avviarlo-e-verificarlo-a-mano). |
| `Your user name and password are not defined` (SQLSTATE 28000) | Credenziali sbagliate, o uno zip-kit Firebird senza un `SYSDBA` utilizzabile (vedi [Build e test](https://github.com/danieleteti/mcp-firebird/blob/master/docs/it/development.md)). |
| I tool di analisi non restituiscono niente, o nessuna scansione NATURAL, su un DB **remoto** | Controlla che `firebird.host` sia l'host vero: l'analizzatore dei piani usa l'host configurato. |
| `fbclient.dll` non trovato, o bitness sbagliata | Punta `firebird.client_lib` a un `fbclient.dll` **Win64**; un client 5.0 va bene dal 2.5 al 5.0. |
| Su stdout finisce roba che non è JSON | Il log deve andare solo su file: tieni `logger.config.file=loggerpro.stdio.json`. |
| Porta 3050 già occupata da un altro Firebird | Usane un'altra (è il motivo per cui l'harness di test mette FB 2.5 sulla **3070**). |

---

## Innocuo per il database, e compatibile

- **Sola lettura, e non sulla fiducia.** Il server apre le sue transazioni in sola lettura:
  INSERT, UPDATE, DELETE e DDL li rifiuta Firebird, non un nostro controllo che potrebbe
  sbagliarsi su cosa fa uno statement. Conta perché quattro tool eseguono SQL che arriva come
  testo da chi chiama: `fb_query` ne restituisce le righe, `fb_analyze_query` misura la SELECT
  che analizza, `fb_suggest_indexes` misura quella su cui dà consigli e `fb_evaluate_goal` ne
  cronometra una. Tutti e quattro rifiutano già tutto ciò che non è una SELECT semplice prima di
  eseguirlo, e rifiutano di eseguire uno statement con parametri che nessuno ha valorizzato; la
  transazione read-only è quello che regge se un rifiuto sbaglia.

  L'ordine conta, ed è il contrario di una blocklist di parole chiave. Una lista di parole
  vietate — niente `INSERT`, niente `DROP` — è un'ipotesi sul testo: non sa che `EXECUTE
  PROCEDURE` può scrivere, che uno statement si può comporre in modo da non contenere nessuna di
  quelle parole, né che la prossima release aggiunge una keyword che nessuno ha aggiunto alla
  lista. Il TPB read-only non è un'ipotesi. Qualunque testo arrivi, qualunque cosa significhi, la
  transazione in cui gira non può scrivere, e a dirlo è il motore. L'SQL che ti
  propone un'indicazione lo lanci tu, quando e se decidi di farlo. I tool che applicano da soli
  una modifica sono in programma: quando arriveranno, saranno spenti finché non li accendi tu.
- **Tutte le versioni.** Il rilevamento delle funzionalità adatta al motore connesso quello che il
  server usa (tabelle MON$, piani con explain, BOOLEAN, INT128, fusi orari, worker paralleli).
  Validato su FB 2.5 / 3.0 / 4.0 / 5.0.
- **Un solo database configurato** per istanza: se ti servono più DB, avvii più istanze.

---

## Licenza

Dalla **v0.2.0** la licenza è la
**[PolyForm Internal Use License 1.0.0](https://github.com/danieleteti/mcp-firebird/blob/master/LICENSE)**: gratuito sui tuoi database, a qualunque
scala, e serve una licenza solo per passare il software a qualcun altro. **La v0.1.0 e le precedenti
sono uscite sotto Apache-2.0, e sotto Apache-2.0 restano** per chi le ha ricevute. Cosa vuol dire in
pratica: [Edizioni e licenze](https://github.com/danieleteti/mcp-firebird/blob/master/docs/it/editions.md) e [`NOTICE`](https://github.com/danieleteti/mcp-firebird/blob/master/NOTICE).

Costruito con **[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi)**, che a sua
volta poggia su **[DelphiMVCFramework](https://github.com/danieleteti/delphimvcframework)**. Questo
server è un esempio completo e reale di cosa ci si può costruire: se vuoi scriverti un server MCP in
Delphi, parti da lì.
