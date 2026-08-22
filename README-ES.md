**[English](README.md) · [Italiano](README-IT.md) · [Español](README-ES.md) · [Deutsch](README-DE.md)**

<p align="center">
  <img src="https://raw.githubusercontent.com/danieleteti/mcp-firebird/master/docs/logo.png" alt="MCP Firebird" width="360">
</p>

<p align="center">
  <a href="https://github.com/danieleteti/mcp-firebird/blob/master/LICENSE"><img alt="Licencia: PolyForm Internal Use 1.0.0" src="https://img.shields.io/badge/License-PolyForm_Internal_Use-blue.svg"></a>
  <img alt="Protocolo MCP 2025-03-26" src="https://img.shields.io/badge/MCP-2025--03--26-brightgreen.svg">
  <a href="https://github.com/danieleteti/mcp-server-delphi"><img alt="powered by mcp-server-delphi" src="https://img.shields.io/badge/powered%20by-mcp--server--delphi-orange.svg"></a>
  <a href="https://github.com/danieleteti/mcp-firebird/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/danieleteti/mcp-firebird/actions/workflows/ci.yml/badge.svg"></a>
</p>

# MCP Firebird

**Pregúntale a tu asistente de IA por qué una query es lenta, y obtén una respuesta que puedas usar.**

Un servidor [Model Context Protocol](https://modelcontextprotocol.io) para **Firebird 2.5 a 5.0**.
Apúntalo a una base de datos y tu asistente lee los planes de acceso reales, te dice qué índice
falta y cuáles cuatro sobran, audita la salud de una tabla y encuentra la transacción que lleva
desde el martes frenando la recolección de basura.

Las respuestas salen de *tu* base de datos, no de un artículo: el servidor le pide el plan a
Firebird (`SET PLANONLY`), lee las tablas de monitorización (`MON$`), y cuenta cuántos valores
distintos tiene realmente una columna antes de afirmar que indexarla compensa. Cada respuesta llega
como **Finding** (qué falla), **SQL** (la sentencia que lo arregla) y **Verify** (cómo comprobar que
funcionó). En tu base de datos no se escribe nada: el servidor se conecta en solo lectura, y el SQL
que te entrega lo ejecutas tú, si decides hacerlo.

- **Transporte:** stdio (JSON-RPC 2.0, MCP `2025-03-26`) · **Identidad del servidor:** `mcp-firebird` v`0.5.0`
- **Motores:** Firebird 2.5, 3.0, 4.0, 5.0 — detectados en tiempo de ejecución
- **Gratis** en tus propias bases de datos, a cualquier escala, sin clave y sin caducidad. La
  licencia solo hace falta para que el software salga de tus manos
  ([detalles](https://github.com/danieleteti/mcp-firebird/blob/master/docs/es/editions.md))

---

## Inicio rápido

Cinco minutos, cuatro pasos. Windows x64.

**1. Consigue el servidor.** Descarga la [última release](https://github.com/danieleteti/mcp-firebird/releases)
y descomprímela, por ejemplo en `C:\Tools\MCPFirebird`.
Si prefieres compilarlo: [Compilar y probar](https://github.com/danieleteti/mcp-firebird/blob/master/docs/es/development.md).  <!-- release:drop -->

**2. Dile cuál es la base de datos.** Copia `.env.example` junto al exe como `.env` y rellena
cuatro líneas:

```ini
firebird.database=C:\data\MYAPP.FDB
firebird.user=SYSDBA
firebird.password=masterkey
firebird.client_lib=C:\Program Files\Firebird\Firebird_5_0\fbclient.dll
```

El zip no trae ningún `fbclient.dll`, a propósito: el correcto es la librería cliente de tu propio
servidor.

**3. Regístralo en tu agente de IA.** Es un servidor stdio — el exe lo arranca el agente, así que
toda la instalación es un comando. Claude Code:

```powershell
claude mcp add firebird -- "C:\Tools\MCPFirebird\MCPFirebird.exe"
```

Claude Desktop (`%APPDATA%\Claude\claude_desktop_config.json`), Cursor (`.cursor/mcp.json`) y
VS Code (`.vscode/mcp.json`) usan la misma forma:

```json
{ "mcpServers": { "firebird": { "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe" } } }
```

Gemini CLI y OpenCode cambian un poco — los fragmentos de cada cliente están en
[Instalación](https://github.com/danieleteti/mcp-firebird/blob/master/docs/es/setup.md#instalarlo-en-tu-agente-de-ia-claude-gemini-cursor-).

**4. Pregúntale algo.**

> **Tú:** ¿A qué versión de Firebird estoy conectado, y qué tablas hay en la base de datos?
>
> **Tú:** Esta query es lenta, ¿por qué? `SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'`
>
> **Tú:** Sugiéreme un índice que lo arregle.

La instalación es esto. Si el cliente muestra el servidor pero ninguna herramienta, mira
**Resolución de problemas**, al final de esta página.

---

## Qué puedes pedirle

| Pides | Qué ocurre |
|---|---|
| *"Documenta la tabla CUSTOMERS"* | Documentación Markdown: columnas, PK, índices, triggers. Sin nombre de tabla obtienes toda la base de datos, procedimientos y paquetes incluidos |
| *"¿Por qué es lenta esta query?"* | El plan de acceso, los NATURAL y los SORT externos que contiene, el plan explicado por el motor en 3.0+, **y** cuánto costó de verdad ejecutándola una vez |
| *"Sugiéreme un índice"* | El remedio más barato que explica el plan — refrescar estadísticas viejas, despertar un índice inactivo, o crear uno — y **"ningún índice, aquí el escaneo es correcto"** con los números, cuando esa es la respuesta |
| *"¿Qué índices puedo borrar?"* | Duplicados, prefijos redundantes, índices inactivos y de baja selectividad, con el `DROP INDEX` y el paso de verificación |
| *"Audita esta tabla"* | Clave primaria ausente, exceso de índices, estadísticas viejas |
| *"Sigue optimizando hasta que esta query deje de hacer NATURAL"* | El bucle por objetivo: cambia, vuelve a medir sobre la base de datos, y para cuando lo dice la medida — no cuando lo cree el asistente |
| *"Cada tarde se arrastra y nadie ha tocado nada"* | Clasifica el síntoma antes de tocar una herramienta, y luego muestrea `MON$` sobre una ventana para enseñar qué se acumula |
| *"¿Quién está conectado, y qué está ejecutando?"* | Cada conexión con su usuario, dirección y proceso, la sentencia que ejecuta ahora mismo y desde cuándo |
| *"Haz una copia de seguridad"* | Ejecuta `gbak` en segundo plano y **restaura lo que ha escrito en una base de datos desechable**: la respuesta no es "existe un fichero" sino "este backup se restaura" |

Cada análisis cierra además diciendo **qué no ha descartado**: un plan no ve la contención, y una
instantánea no ve la acumulación.

**[→ Ejemplos reales, salida literal de las herramientas, una vuelta completa sobre `employee.fdb`](https://github.com/danieleteti/mcp-firebird/blob/master/docs/es/usage.md)**

---

## Las herramientas

Trece herramientas, tres prompts, un recurso. Referencia completa — argumentos, qué decide cada una,
las llamadas `tools/call` en crudo — en
**[docs/es/tools.md](https://github.com/danieleteti/mcp-firebird/blob/master/docs/es/tools.md)**.

`fb_info` · `fb_list_tables` · `fb_generate_documentation` · `fb_analyze_query` ·
`fb_suggest_indexes` · `fb_suggest_index_drops` · `fb_audit_table` · `fb_evaluate_goal` ·
`fb_monitor_transactions` · `fb_sample_activity` · `fb_monitor_attachments` ·
`fb_backup_start` · `fb_backup_status`

`fb_backup_start` vuelve antes que el backup — luego haz polling con `fb_backup_status`. Necesita
`firebird.backup_dir` en el `.env`, `gbak.exe` junto a tu `fbclient.dll`, y sitio en ese disco para
una segunda copia de la base de datos mientras corre la restauración de verificación.

Prompts: `optimization_goal` (itera hasta cumplirlo) · `health_check` · `classify_problem`.
Recurso: `firebird://schema`.

Otras nueve herramientas aparecen en `tools/list` y pertenecen a la
[edición Enterprise](https://github.com/danieleteti/mcp-firebird/blob/master/docs/es/editions.md#edición-enterprise):
tu asistente las ve y sabe decirte qué haría con ellas.

---

## Ediciones

**Usarlo en tus propias bases de datos es gratis, y sigue siéndolo.** Sin prueba, sin caducidad, sin
clave de licencia, sin contar puestos. Consultores: es vuestra herramienta, usadla en las bases de
datos de vuestros clientes y cobrad vuestro tiempo. Lo único que necesita licencia es **que una copia
salga de vuestras manos** — redistribuirlo, incrustarlo en un producto que vendéis, u ofrecerlo como
servicio.

La **edición Enterprise**, de pago, recoge donde termina una conexión SQL: `firebird.conf`, la RAM y
las CPU de la máquina, `firebird.log`, la Trace API, el informe de almacenamiento físico. La quieres
cuando el esquema está en orden y la base de datos sigue lenta.

**[→ Ediciones, licencias y los casos concretos](https://github.com/danieleteti/mcp-firebird/blob/master/docs/es/editions.md)** · d.teti@bittime.it

---

## Documentación

| | |
|---|---|
| [Instalación](https://github.com/danieleteti/mcp-firebird/blob/master/docs/es/setup.md) | Requisitos, referencia del `.env`, `--env <dir>`, varias bases de datos desde una instalación, fragmentos por cliente, prueba manual |
| [Ejemplos reales](https://github.com/danieleteti/mcp-firebird/blob/master/docs/es/usage.md) | Las conversaciones, la salida literal de las herramientas, una vuelta de optimización |
| [Referencia de herramientas](https://github.com/danieleteti/mcp-firebird/blob/master/docs/es/tools.md) | Las trece herramientas, cómo decide el asesor de índices, prompts, recursos, Enterprise |
| [Ediciones y licencias](https://github.com/danieleteti/mcp-firebird/blob/master/docs/es/editions.md) | Qué es gratis, qué necesita licencia, qué añade Enterprise |
| [Compilar y probar](https://github.com/danieleteti/mcp-firebird/blob/master/docs/es/development.md) | Compilación Delphi, la matriz de pruebas 2.5→5.0, cómo usa mcp-server-delphi |  <!-- release:drop -->
| [Catálogo de problemas](https://github.com/danieleteti/mcp-firebird/blob/master/docs/firebird-problem-catalog.md) | Cada problema detectado, la fixture que lo provoca, el milestone (en inglés) |

---

## Resolución de problemas

| Síntoma | Causa probable y solución |
|---|---|
| El cliente muestra el servidor pero **ninguna herramienta** | Falta el `.env`, o la base de datos no es accesible: el servidor arranca, pero las herramientas fallan al conectar. Pruébalo con la [prueba manual](https://github.com/danieleteti/mcp-firebird/blob/master/docs/es/setup.md#ejecutar-y-verificar-a-mano). |
| `Your user name and password are not defined` (SQLSTATE 28000) | Credenciales incorrectas, o un zip-kit de Firebird sin un `SYSDBA` utilizable (ver [Compilar y probar](https://github.com/danieleteti/mcp-firebird/blob/master/docs/es/development.md)). |
| Las herramientas de análisis no devuelven nada, o ningún escaneo NATURAL, en una base de datos **remota** | Asegúrate de que `firebird.host` es el host real (el analizador de planes usa el host configurado). |
| No encuentra `fbclient.dll`, o es de otra arquitectura | Pon en `firebird.client_lib` una `fbclient.dll` de **Win64**; un cliente 5.0 funciona contra servidores de 2.5 a 5.0. |
| Aparece ruido no JSON en stdout | El log tiene que ir solo a fichero: mantén `logger.config.file=loggerpro.stdio.json`. |
| El puerto 3050 ya lo ocupa otro Firebird | Usa un puerto distinto (por eso el banco de pruebas pone FB 2.5 en el **3070**). |

---

## Seguridad y compatibilidad

- **Solo lectura, y no por confianza.** El servidor abre sus transacciones en solo lectura: un
  INSERT, UPDATE, DELETE o DDL lo rechaza Firebird, no una comprobación nuestra que podría
  equivocarse sobre lo que hace una sentencia. Importa porque tres herramientas ejecutan SQL que
  llega como texto de quien llama: `fb_analyze_query` mide el SELECT que analiza,
  `fb_suggest_indexes` mide aquel sobre el que aconseja y `fb_evaluate_goal` cronometra uno. Las
  tres rechazan ya todo lo que no sea un SELECT simple antes de ejecutarlo, y se niegan a ejecutar
  una sentencia con parámetros que nadie ha rellenado; la transacción de solo lectura es lo que
  aguanta si un rechazo falla. El SQL
  que te entrega una recomendación lo ejecutas tú, cuando y si lo decides. Están previstas
  herramientas que apliquen el cambio por su cuenta y, cuando lleguen, vendrán desactivadas
  hasta que tú las actives.
- **Multiversión.** La detección de capacidades adapta el uso de las funciones (tablas MON$, planes
  explicados, BOOLEAN, INT128, zonas horarias, workers paralelos) al motor conectado; validado en FB
  2.5 / 3.0 / 4.0 / 5.0.
- **Una sola base de datos configurada** por instancia del servidor (si necesitas varias, ejecuta
  varias instancias).

---

## Licencia

Desde la **v0.2.0** la licencia es la
**[PolyForm Internal Use License 1.0.0](https://github.com/danieleteti/mcp-firebird/blob/master/LICENSE)**: gratis en tus propias bases de datos, a
cualquier escala, y solo hace falta licencia para pasarle el software a otra persona. **La v0.1.0 y
anteriores salieron bajo Apache-2.0, y así siguen** para quien las recibió. Qué significa en la
práctica: [Ediciones y licencias](https://github.com/danieleteti/mcp-firebird/blob/master/docs/es/editions.md) y [`NOTICE`](https://github.com/danieleteti/mcp-firebird/blob/master/NOTICE).

Construido con **[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi)**, que a su
vez se apoya en **[DelphiMVCFramework](https://github.com/danieleteti/delphimvcframework)**. Este
servidor es un ejemplo completo y real de lo que puedes construir con ellos: si vas a escribir tu
propio servidor MCP en Delphi, empieza ahí.
