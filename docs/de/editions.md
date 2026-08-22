# Editionen & Lizenzierung

[← zurück zur README](../../README-DE.md)

Kurzfassung: **wenn du es auf deinen eigenen Datenbanken einsetzt, ist es kostenlos, und das bleibt
so.** Keine Testphase, kein Ablaufdatum, kein Lizenzschlüssel, keine Nutzerzählung, keine Grenze für
Tabellen oder Datenbanken. Installier es, setz es in Produktion ein, benutz es täglich. Nichts
telefoniert nach Hause.

Das Einzige, was du nicht darfst: es jemand anderem in die Hand geben.

MCP Firebird ist **source-available, nicht Open Source** im Sinne der Definition der Open Source
Initiative. Das klar zu sagen ist wichtiger als ein Badge: ab **v0.2.0** gilt die
[PolyForm Internal Use License 1.0.0](../../LICENSE). Alle Versionen bis einschließlich **v0.1.0 erschienen
unter Apache-2.0 und bleiben es** für jeden, der sie erhalten hat. Eine einmal erteilte Lizenz lässt
sich nicht widerrufen, und dieses Projekt tut auch nicht so.

### Was du kostenlos darfst

- Es gegen jede beliebige Datenbank laufen lassen: deine, die deines Arbeitgebers, die deines Kunden.
  Entwicklung, Staging, Produktion, alle.
- Es in jeder Größenordnung einsetzen. Hundert Tabellen oder zehntausend, eine Datenbank oder fünfzig.
- **Es in deiner Beratungstätigkeit einsetzen.** Diagnostiziere, tune, prüfe und betreue damit die
  Firebird-Datenbanken deiner Kunden, und stell ihnen deine Zeit in Rechnung. Es ist dein Werkzeug,
  behalt es.
- Den Quellcode lesen. Den ganzen. Lern daraus, und nutz, was du gelernt hast.
- Es ändern. Einen Bug beheben, einen Detektor ergänzen, eine Meldung umformulieren. Deinen eigenen
  Build laufen lassen.
- Es in einem Unternehmen jeder Größe einsetzen, kommerziell oder nicht, gewinnorientiert oder nicht,
  ohne Gebühr und ohne Registrierung.

### Wofür eine Lizenz nötig ist

Ein Gedanke in drei Formen: **die Software aus der Hand geben.**

- **Weitergabe.** Einen Fork veröffentlichen, einen Build hochladen, ihn auf eine CD packen, die
  Binärdatei an einen Kunden schicken, sie nach Projektende auf dem Server des Kunden liegen lassen.
- **Einbau in ein Produkt, das du verkaufst.** Ausliefern in deinem ERP, deinem Installer, deinem
  Docker-Image, deiner Appliance, als Quellcode oder als Binärdatei, verändert oder nicht.
- **Angebot als Dienst.** Betrieb hinter einer API oder einem gehosteten Agenten, den Leute außerhalb
  deiner Organisation erreichen können.

Wo die Software läuft und wessen Datenbank sie untersucht, ist deine Sache. Wo Kopien davon landen,
ist unsere.

Trifft einer dieser Fälle auf dich zu, dann gibt es die Lizenz, und gemessen an dem, was du damit
baust, ist sie nicht teuer. Schreib an **d.teti@bittime.it**.

### Wann du eine Lizenz kaufen musst: durchgespielte Fälle

| Deine Situation | Lizenz nötig? |
|---|---|
| Dein DBA lässt es jeden Morgen gegen das Firebird-Produktivsystem der Firma laufen | **Nein.** |
| Deine vierzig Entwickler lassen es jeweils lokal laufen | **Nein.** Keine Nutzerzählung, keine Registrierung. |
| Du bist Berater und lässt es von deinem Laptop aus gegen die Datenbank deines Kunden laufen | **Nein.** Es ist dein Werkzeug und bleibt dein Werkzeug. Berechne dafür, was du willst. |
| Dasselbe, aber du sitzt beim Kunden und lässt es auf dessen Server laufen | **Nein.** Nimm es mit, wenn du gehst. |
| Du lässt beim Weggehen eine Kopie auf dem Server deines Kunden installiert zurück | **Ja.** Die Software hat deine Hand verlassen. |
| Du bist Hosting-Anbieter und lässt es gegen die Datenbanken laufen, die du hostest | **Nein.** |
| ...und du gibst deinen Kunden einen Button, der es für sie ausführt | **Ja.** Das ist ein Angebot als Dienst. |
| Du lieferst es in deinem Delphi-ERP mit, damit deine Kunden "KI-Datenbanktuning" bekommen | **Ja.** Einbau in ein Produkt, das du lieferst. |
| Du veröffentlichst einen Fork mit deinen Verbesserungen auf GitHub | **Ja.** Sprich vorher mit uns: wir würden ihn lieber mergen. |
| Du schreibst einen Blogartikel, einen Vortrag oder einen Universitätskurs darüber | **Nein.** Lies es, zitier es, unterrichte es. |
| Du bist auf `v0.1.0`, das du unter Apache-2.0 erhalten hast | **Nein.** Diese Version bleibt für dich für immer Apache-2.0. |

Die Regel hinter der Tabelle, falls du lieber denkst als nachschlägst: **frag, wo die Software landet,
nie, was du damit gemacht hast.** Solange jede Kopie von MCP Firebird in deiner Hand bleibt, schuldest
du nichts: nicht für die Größenordnung, in der du sie einsetzt, nicht für das Geld, das sie dir
einbringt, nicht dafür, auf wessen Datenbank du sie ansetzt. In dem Moment, in dem eine Kopie dich
verlässt, sollten wir reden.

Daneben gibt es die kostenpflichtige **[Enterprise Edition](#enterprise-edition)**, ein eigenes
Produkt und keine beschnittene Gratisstufe. Alles, was im Rest dieser README beschrieben wird, steckt
in der freien Edition.

## Enterprise Edition

### Wo die freie Edition endet

Die freie Edition ist keine Demo, und sie ist auch nicht die Enterprise Edition ohne die guten Teile.
Sie erledigt eine Aufgabe vollständig und ordentlich: **sie bringt die Datenbank dazu, für sich selbst
Rechenschaft abzulegen.**

Sie liest dein Schema. Sie erklärt deine Pläne. Sie findet den Index, der dir fehlt, und die vier, die
du nicht brauchst. Sie erwischt den fehlenden Primärschlüssel, die veralteten Statistiken, die
Transaktion, die seit Dienstag die Garbage Collection festhält. Bei den meisten Datenbanken liegt das
Problem meistens genau dort, und dort wird es auch behoben. Viele werden sie jahrelang benutzen und nie
etwas anderes brauchen, und niemand wird je einen Cent von ihnen verlangen.

Und dann kommt der Tag, an dem sie dir die Wahrheit sagt: *dein Schema ist in Ordnung. Deine Indizes
sind in Ordnung. Keine NATURAL-Scans, keine externen Sorts, Statistiken frisch.* Und die Datenbank ist
immer noch langsam.

**Das ist die Grenze.** Die freie Edition hat ihre Frage ehrlich und vollständig beantwortet, und die
Antwort lautet: das Problem liegt nicht in der Datenbank. Es liegt in der Maschine darunter, und kein
`SELECT` wird dir das je zeigen. Nicht weil das Tool etwas zurückhielte, sondern weil SQL nicht über
seinen eigenen Prozess hinaussehen kann.

### Wo die Enterprise Edition beginnt

Es sind 2 GB Page Buffers auf einem Host mit 8 GB RAM. Es sind die Forced Writes, vor zwei Jahren für
einen Batch-Load abgeschaltet und nie wieder eingeschaltet. Es sind `LockHashSlots`, immer noch auf dem
Standardwert von 2010, bei vierhundert Verbindungen, ein vier Ebenen tiefer Index, ein Bugcheck, der
jeden Dienstag um 03:00 ins `firebird.log` geschrieben wird und den niemand liest.

Die freie Edition verbindet sich mit Firebird genau wie deine Anwendung: eine gewöhnliche
SQL-Verbindung mit gewöhnlichen Rechten. **Die Enterprise Edition verlangt mehr.** Sie hängt sich als
Administrator an den Services Manager (so streamt sie `firebird.log` zurück, steuert die Trace API und
liest den physischen Storage-Report), und sie liest die Konfiguration und die Hardware des Servers
selbst. Das ist ein anderes Privileg, ein anderer Schadensradius und ein anderes Gespräch mit dem, dem
der Server gehört. Deshalb ein anderes Produkt.

Und sie bleibt nicht dabei stehen, dir zu sagen, was falsch ist. **Sie führt das Experiment durch.**
Eine Baseline unter echter Last aufnehmen, genau einen Parameter ändern, erneut messen, die
Verteilungen vergleichen (p95 und p99, niemals den Mittelwert) und die Änderung behalten oder
zurücknehmen. Niemand verkauft dir eine Zahl. Die Zahl nennt dir die Datenbank.

| | Free | Enterprise |
|---|---|---|
| Schema, Doku, Pläne, Index-Beratung, Schema-Audit | ✅ | ✅ |
| Zustand von Transaktionen und Sweep (`MON$`) | ✅ | ✅ |
| `fb_diagnose`: der Einstiegspunkt, was schon bekannt ist und die geordnete Route, die als Nächstes zu gehen ist | ✗ | ✅ |
| `fb_analyze_config`: `firebird.conf` / `databases.conf`, gelesen gegen diese Engine, diese Architektur, diese Last | ✗ | ✅ |
| `fb_analyze_storage`: Indextiefe, Füllgrad der Seiten, Satzversionsketten, Seitenverteilung | ✗ | ✅ |
| `fb_parse_log` (`firebird.log`): Fehler, Sweeps, Bugchecks, Abstürze | ✗ | ✅ |
| `fb_capture_trace` (Trace API): die echte Last, und was sie wirklich kostet | ✗ | ✅ |
| `fb_trace_start` / `fb_trace_status` / `fb_trace_stop`: das lange Fenster, bis zu zwei Stunden Trace, im Hintergrund abgeleitet | ✗ | ✅ |
| `fb_analyze_host`: RAM gegen Page Buffers, CPU gegen parallele Worker, Storage-Klasse | ✗ | ✅ |
| Baselines, Verteilungen, Vorher/Nachher-Vergleich: das Experiment | ✗ | ✅ |

Beachte, was *nicht* in dieser Tabelle steht: nichts wurde aus der freien Edition herausgenommen, um
die kostenpflichtige zu bauen. Jedes freie Tool bleibt frei, und die noch ungeschriebenen bleiben auf
der Seite der Grenze, auf die sie gehören. Die Grenze ist keine Paywall quer durch eine Featureliste.
Sie verläuft zwischen dem Abfragen einer Datenbank und dem Administrieren eines Servers, und die freie
Edition stand immer auf der einen Seite davon.

Das Schwierige war nie, `firebird.conf` zu parsen; eine INI-Datei kann jeder parsen. Und niemand kann
dir ehrlichen Gewissens den richtigen Wert für `LockHashSlots` nennen: **Firebirds eigene Dokumentation
gibt dafür kein Optimum an**, auch nicht für den Page Cache und nicht für den Sort Cache. Was Erfahrung
dir kauft, ist das Wissen, *welchen* Parameter dein Symptom belastet: bricht der Durchsatz unter
Nebenläufigkeit ein, während die CPU ruhig bleibt, dann deutet das auf die Lock-Tabelle und nie auf den
Page Cache. Diese Landkarte ist das Produkt. Der Wert am Ende des Wegs wird nicht behauptet. Er wird
gemessen, auf deiner Datenbank, unter deiner Last.

Du wirst merken, wann du sie brauchst, denn die freie Edition wird es dir gesagt haben.

Die neun Tools oben erscheinen schon in der freien Edition in `tools/list`, dein Assistent sieht sie
also und kann sagen, was er mit ihnen täte. Rufst du eines auf, erklärt es dir, wie du es bekommst.

**Enterprise-Lizenzen, kommerzielle Lizenzen und Support-Abos:** d.teti@bittime.it
