# Edizioni e licenze

[← torna al README](../../README-IT.md)

In breve: **sui tuoi database è gratuito, e gratuito resta.** Nessuna prova a tempo, nessuna
scadenza, nessuna chiave, nessun conteggio di postazioni, nessun limite al numero di tabelle o di
database. Installalo, mettilo in produzione, usalo tutti i giorni. Non contatta nessun server.

L'unica cosa che non puoi fare è darlo a qualcun altro.

MCP Firebird è **source-available, non open source** nel senso che dà al termine la Open Source
Initiative. Dirlo chiaro conta più di un badge: dalla **v0.2.0** la licenza è la
[PolyForm Internal Use License 1.0.0](../../LICENSE). Le versioni fino alla **v0.1.0 sono uscite sotto
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
| Grant registrati nel database (`fb_audit_security`): PUBLIC, grant option, ruoli inutilizzati | ✅ | ✅ |
| `fb_diagnose`: il punto di ingresso, cosa si sa già e il percorso ordinato da seguire | ❌ | ✅ |
| `fb_analyze_config`: `firebird.conf` e `databases.conf`, letti per questo motore, questa architettura, questo carico | ❌ | ✅ |
| `fb_analyze_storage`: profondità degli indici, riempimento delle pagine, catene di versioni dei record, distribuzione delle pagine | ❌ | ✅ |
| `fb_parse_log`: `firebird.log`, ovvero errori, sweep, bugcheck, crash | ❌ | ✅ |
| `fb_capture_trace`: Trace API, ovvero il carico vero, e quanto costa davvero | ❌ | ✅ |
| `fb_trace_start` / `fb_trace_status` / `fb_trace_stop`: la finestra lunga, fino a due ore di trace drenate in background | ❌ | ✅ |
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

I nove tool qui sopra compaiono già in `tools/list` nell'edizione free: il tuo assistente li vede
e sa dirti cosa ci farebbe. Se ne chiami uno, ti spiega come averlo.

**Licenze Enterprise, licenze commerciali e contratti di supporto:** d.teti@bittime.it
