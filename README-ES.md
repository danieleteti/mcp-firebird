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

**Pregúntale a tu asistente de IA por qué una query va lenta y recibe una respuesta que sirve para actuar.**

Un servidor [Model Context Protocol](https://modelcontextprotocol.io) para **Firebird 2.5 a 5.0**,
escrito en Delphi sobre el driver oficial `fbclient`. Conéctalo a una base de datos y el asistente
podrá leer tus planes de acceso, decirte qué índices faltan y cuáles sobran, auditar la salud de una
tabla y encontrar las transacciones abiertas que están frenando la garbage collection.

También puedes darle un objetivo, *"esta query tiene que dejar de escanear NATURAL"*, *"tiene que
bajar de 200 ms"*, y dejarlo trabajar: aplica un cambio, lo vuelve a medir contra la base de datos y
lo intenta otra vez si no bastó. Quien decide si el objetivo se cumple es la medición, no el
asistente.

No son los consejos genéricos sobre índices que encuentras en cualquier artículo. Las respuestas
salen de *tu* base de datos: el servidor le pide a Firebird el plan de ejecución de la query
(`SET PLANONLY`), consulta las tablas de monitorización (`MON$`) y cuenta cuántos valores distintos
contiene realmente una columna antes de afirmar que indexarla compensa.

Cada respuesta llega en tres partes. **Finding**: qué ha encontrado y por qué es un problema.
**SQL**: la sentencia que lo corrige, ya escrita. **Verify**: cómo comprobar que la corrección
funcionó. Ninguna herramienta escribe en la base de datos. El servidor lee, y el SQL que te entrega
lo ejecutas tú, cuando y si lo decides.

> Construido con **[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi)**, que a su
> vez se apoya en **[DelphiMVCFramework](https://github.com/danieleteti/delphimvcframework)**. Este
> servidor es un ejemplo completo y real de lo que puedes construir con ellos.

- **Transporte:** stdio (JSON-RPC 2.0, protocolo MCP `2025-03-26`)
- **Identidad del servidor:** `mcp-firebird` v`0.2.4`
- **Motores soportados:** Firebird 2.5, 3.0, 4.0, 5.0 (capacidades detectadas en tiempo de ejecución)
- **Seguridad:** análisis de solo lectura; ninguna herramienta ejecuta DDL ni SQL de escritura
- **Gratis** para tus propias bases de datos, a cualquier escala, sin clave y sin caducidad. La
  licencia solo hace falta para poner el software en manos de otro: revenderlo dentro de un producto
  tuyo, dejarlo instalado en casa de un cliente, exponerlo como servicio
  ([detalles de la licencia](#ediciones-y-licencias))
- **[Edición Enterprise](#edición-enterprise)**, de venta aparte: examina el *servidor* Firebird, no
  solo la base de datos. Lee `firebird.conf`, la RAM y las CPU de la máquina, `firebird.log` y la
  Trace API. La quieres cuando el esquema está en orden y la base de datos sigue lenta

---

## Índice

1. [Qué hace](#qué-hace)
2. [Ediciones y licencias](#ediciones-y-licencias)
3. [Edición Enterprise](#edición-enterprise)
4. [Cómo usa mcp-server-delphi](#cómo-usa-mcp-server-delphi)  <!-- release:drop -->
5. [Requisitos](#requisitos)
6. [Compilación](#compilación)  <!-- release:drop -->
7. [Configuración (`.env`)](#configuración-env)
8. [Ejecutar y verificar a mano](#ejecutar-y-verificar-a-mano)
9. [Instalarlo en tu agente de IA](#instalarlo-en-tu-agente-de-ia-claude-gemini-cursor-): Claude Desktop · Claude Code · Gemini CLI · OpenCode · Cursor / VS Code · genérico
10. [Usarlo desde Claude](#usarlo-desde-claude): ejemplos reales
11. [Referencia de herramientas](#referencia-de-herramientas)
12. [Probar el proyecto](#probar-el-proyecto)  <!-- release:drop -->
13. [Resolución de problemas](#resolución-de-problemas)

---

## Qué hace

### Herramientas (9 gratuitas, más 5 Enterprise anunciadas en `tools/list`)

| Herramienta | Argumentos | Para qué sirve |
|---|---|---|
| `fb_info` | *(ninguno)* | Versión del motor y capacidades detectadas (JSON) |
| `fb_list_tables` | *(ninguno)* | Lista las tablas de usuario |
| `fb_generate_documentation` | `table_name?` | Documentación Markdown (columnas, PK, índices) de una tabla, o de toda la base de datos |
| `fb_analyze_query` | `sql` | Análisis del plan de acceso: detecta escaneos NATURAL y SORT externos |
| `fb_suggest_indexes` | `sql` | Propone índices nuevos a partir de los predicados escaneados en NATURAL (DDL listo para ejecutar) |
| `fb_suggest_index_drops` | `table_name` | Señala índices duplicados, con prefijo redundante, inactivos o de baja selectividad |
| `fb_audit_table` | `table_name` | Auditoría de salud del esquema: PK ausente, exceso de índices, estadísticas obsoletas |
| `fb_evaluate_goal` | `goal_type`, `target`, `threshold` | Comprobación determinista del objetivo (es lo que mueve el bucle de optimización) |
| `fb_monitor_transactions` | `stale_minutes?` | Salud de transacciones y sweep: distancia OIT/OAT/Next, transacciones largas que bloquean (con su última sentencia SQL) |

Cada recomendación viene con un **Finding**, el **SQL** listo para ejecutar y un paso de **Verify**.

### Prompts (2)

- **`optimization_goal`**, el bucle guiado por objetivos: fija una meta y el asistente itera sobre
  las herramientas `fb_*` y vuelve a comprobar `fb_evaluate_goal` hasta que devuelve `met: true`
  (con una parada de seguridad por máximo de iteraciones o por falta de progreso).
- **`health_check`**: revisión guiada de la salud de toda la base de datos.

### Recursos (1)

- **`firebird://schema`**: el esquema vivo de la base de datos como un único recurso.

---

## Ediciones y licencias

En corto: **si lo usas sobre tus propias bases de datos, es gratis, y seguirá siéndolo.**
Sin prueba limitada, sin caducidad, sin clave de licencia, sin recuento de puestos, sin límite de
tablas ni de bases de datos. Instálalo, úsalo en producción, úsalo todos los días. No llama a casa.

Lo único que no puedes hacer es entregárselo a otro.

MCP Firebird es **source-available, no open source** en el sentido que le da la Open Source
Initiative. Decirlo claro importa más que una insignia: desde la **v0.2.0** se distribuye bajo la
[PolyForm Internal Use License 1.0.0](LICENSE). Las versiones hasta la **v0.1.0 incluida se
publicaron bajo Apache-2.0 y lo siguen estando** para todo el que las recibió: una licencia ya
concedida no se revoca, y este proyecto no finge lo contrario.

### Qué puedes hacer sin pagar nada

- Ejecutarlo contra la base de datos que quieras: la tuya, la de tu empresa, la de tu cliente. En
  desarrollo, en staging, en producción.
- Ejecutarlo a cualquier escala. Cien tablas o diez mil; una base de datos o cincuenta.
- **Usarlo en tu trabajo de consultoría.** Diagnostica, ajusta, audita y da soporte a las bases de
  datos Firebird de tus clientes con él, y cóbrales tu tiempo. Es tu herramienta; quédatela.
- Leer el código. Todo. Aprender de él y usar lo aprendido.
- Modificarlo. Corregir un bug, añadir un detector, cambiar un mensaje. Ejecutar tu propia
  compilación.
- Usarlo en una empresa de cualquier tamaño, comercial o no, con o sin ánimo de lucro, sin coste y
  sin registro.

### Qué requiere licencia

Una sola idea, dicha de tres maneras: **que el software salga de tus manos.**

- **Redistribuirlo.** Publicar un fork, subir un binario, meterlo en un CD, enviárselo a un cliente,
  dejarlo instalado en el servidor de un cliente cuando termina el encargo.
- **Integrarlo en un producto que vendes.** Incluirlo en tu ERP, tu instalador, tu imagen Docker, tu
  appliance, en código o en binario, modificado o no.
- **Ofrecerlo como servicio.** Ponerlo detrás de una API o de un agente alojado al que llegue gente
  de fuera de tu organización.

Dónde se ejecuta el software, y qué base de datos examina, es asunto tuyo. Dónde acaban las copias es
asunto nuestro.

Si tu caso es uno de estos, la licencia existe y no es cara comparada con lo que estás construyendo
con ella. Escribe a **d.teti@bittime.it**.

### Cuándo hay que comprar licencia: casos reales

| Tu situación | ¿Hace falta licencia? |
|---|---|
| Tu DBA lo ejecuta cada mañana contra el Firebird de producción de la empresa | **No.** |
| Tu equipo de cuarenta desarrolladores lo ejecuta cada uno en local | **No.** Sin puestos, sin registro. |
| Eres consultor y lo ejecutas desde tu portátil contra la base de datos de tu cliente | **No.** Es tu herramienta y sigue siendo tuya. Cóbrale lo que quieras. |
| Lo mismo, pero estás sentado en la mesa del cliente, ejecutándolo en su servidor | **No.** Llévatelo contigo cuando te vayas. |
| Dejas una copia instalada en el servidor de tu cliente al marcharte | **Sí.** El software salió de tus manos. |
| Eres proveedor de hosting y lo ejecutas contra las bases de datos que alojas | **No.** |
| ...y además das a tus clientes un botón que lo ejecuta por ellos | **Sí.** Eso es ofrecerlo como servicio. |
| Lo incluyes dentro de tu ERP en Delphi para que tus clientes tengan "ajuste de base de datos con IA" | **Sí.** Integración en un producto que suministras. |
| Publicas un fork en GitHub con tus mejoras | **Sí.** Habla con nosotros antes: preferimos integrarlo. |
| Escribes un artículo, una charla o un curso universitario sobre él | **No.** Léelo, cítalo, enséñalo. |
| Estás en la `v0.1.0`, que obtuviste bajo Apache-2.0 | **No.** Esa versión seguirá siendo Apache-2.0 para ti siempre. |

La regla que hay detrás de la tabla, por si prefieres razonar a consultar: **pregunta dónde acaba el
software, nunca qué hiciste con él.** Mientras cada copia de MCP Firebird siga en tus manos, no debes
nada: ni por la escala a la que lo ejecutas, ni por el dinero que te haga ganar, ni por la base de
datos a la que lo apuntes. En cuanto una copia sale, tenemos que hablar.

Existe además una **[edición Enterprise](#edición-enterprise)** de pago, que es un producto distinto
y no una versión gratuita mutilada. Todo lo que describe el resto de este README está en la gratuita.

---

## Edición Enterprise

### Dónde termina la edición gratuita

La edición gratuita no es una demo, ni la Enterprise con las partes buenas quitadas. Es un trabajo
entero, hecho bien: **hace que la base de datos responda por sí misma.**

Lee tu esquema. Explica tus planes. Encuentra el índice que te falta y los cuatro que te sobran.
Detecta la clave primaria ausente, las estadísticas obsoletas, la transacción que lleva desde el
martes bloqueando la garbage collection. En la mayoría de las bases de datos, la mayoría de las
veces, ahí está el problema y ahí se arregla. Mucha gente la usará durante años sin necesitar nada
más, y nunca se le pedirá un céntimo.

Hasta que un día vuelve y te dice la verdad: *tu esquema está bien. Tus índices están bien. Ni
escaneos naturales, ni sorts externos, estadísticas frescas.* Y la base de datos sigue lenta.

**Ahí está la línea.** La edición gratuita ha respondido a su pregunta con honestidad y hasta el
final, y la respuesta es que el problema no está en la base de datos. Está en la máquina que hay
debajo, y ningún `SELECT` te lo va a enseñar. No porque la herramienta se guarde nada, sino porque
SQL no ve fuera de su propio proceso.

### Dónde empieza la edición Enterprise

Son 2 GB de page buffers en un host con 8 GB de RAM. Son los `forced writes` que alguien desactivó
hace dos años para una carga masiva y nunca volvió a activar. Es `LockHashSlots` todavía en su valor
por defecto de 2010 con cuatrocientas conexiones encima, un índice de cuatro niveles de profundidad,
un bugcheck escrito en `firebird.log` todos los martes a las 03:00 que nadie lee.

La edición gratuita se conecta a Firebird igual que tu aplicación: una conexión SQL normal, con
permisos normales. **La edición Enterprise pide más.** Se conecta al Services Manager como
administrador (así es como transmite `firebird.log`, maneja la Trace API y lee el informe de
almacenamiento físico) y lee la configuración y el hardware del propio servidor. Eso es otro nivel de
privilegio, otro radio de impacto y otra conversación con quien administra el servidor. De ahí que
sea otro producto.

Y no se queda en decirte qué está mal. **Hace el experimento.** Captura una línea base bajo carga
real, cambia exactamente un parámetro, vuelve a medir, compara las distribuciones (el p95 y el p99,
nunca la media) y conserva el cambio o lo deshace. Aquí nadie te vende un número. El número te lo da
la base de datos.

| | Gratuita | Enterprise |
|---|---|---|
| Esquema, documentación, planes, consejo sobre índices, auditoría del esquema | ✅ | ✅ |
| Salud de transacciones y sweep (`MON$`) | ✅ | ✅ |
| `fb_diagnose`: el punto de entrada, lo que ya se sabe y la ruta ordenada a seguir | ✗ | ✅ |
| `fb_analyze_config`: `firebird.conf` / `databases.conf`, leídos contra este motor, esta arquitectura, esta carga | ✗ | ✅ |
| `fb_analyze_storage`: profundidad de los índices, llenado de las páginas, cadenas de versiones de registro, distribución de páginas | ✗ | ✅ |
| `fb_parse_log` (`firebird.log`): errores, sweeps, bugchecks, caídas | ✗ | ✅ |
| `fb_capture_trace` (Trace API): la carga real, y lo que cuesta de verdad | ✗ | ✅ |
| `fb_trace_start` / `fb_trace_status` / `fb_trace_stop`: la ventana larga, hasta dos horas de trace drenadas en segundo plano | ✗ | ✅ |
| `fb_analyze_host`: RAM frente a page buffers, CPU frente a workers paralelos, clase de almacenamiento | ✗ | ✅ |
| Líneas base, distribuciones, comparación antes/después: el experimento | ✗ | ✅ |

Fíjate en lo que *no* aparece en esa tabla: no se ha sacado nada de la edición gratuita para construir
la de pago. Todas las herramientas gratuitas siguen siendo gratuitas, y las que faltan por escribir
se quedarán del lado de la línea que les toca. La frontera no es un muro de pago trazado sobre una
lista de funciones. Es la línea que separa consultar una base de datos de administrar un servidor, y
la edición gratuita siempre estuvo de un lado.

Lo difícil nunca fue parsear `firebird.conf`; cualquiera parsea un fichero INI. Y nadie te puede dar
honestamente el valor correcto de `LockHashSlots`: **la propia documentación de Firebird no fija un
óptimo para ese parámetro**, ni para la caché de páginas, ni para la de ordenación. Lo que compra la
experiencia es saber *qué* parámetro señala tu síntoma: que el rendimiento se hunda con la
concurrencia mientras la CPU sigue tranquila apunta a la tabla de bloqueos y jamás a la caché de
páginas. Ese mapa es el producto. El valor que hay al final del mapa no se afirma. Se mide, en tu
base de datos y con tu carga.

Sabrás cuándo la necesitas, porque te lo habrá dicho la edición gratuita.

Las nueve herramientas de arriba ya aparecen en `tools/list` en la edición gratuita, así que tu
asistente las ve y puede contarte qué haría con ellas. Si llamas a una, te explica cómo conseguirla.

**Licencias Enterprise, licencias comerciales y suscripciones de soporte:** d.teti@bittime.it


<!-- release:drop -->
## Cómo usa mcp-server-delphi

Cada herramienta es un método Delphi normal decorado con atributos de
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi). El framework convierte la
clase en un proveedor de herramientas MCP, genera el esquema JSON-RPC a partir de los atributos y lo
conecta al transporte stdio: en este repositorio no hay código de protocolo. De
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

Los prompts (`providers/FirebirdPromptsU.pas`) y los recursos (`providers/FirebirdResourcesU.pas`)
siguen el mismo enfoque de atributos. La referencia completa de atributos está en el repositorio de
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi).

---

## Requisitos

- **Windows x64** (el servidor es una aplicación de consola nativa Win64).
- Una **biblioteca cliente de Firebird** (`fbclient.dll`) igual o más reciente que el servidor al que
  apuntas. Una `fbclient.dll` de 5.0 conecta sin problemas con servidores de 2.5 a 5.0.
- Una **base de datos Firebird** accesible a la que apuntar.

La descarga no incluye ninguna `fbclient.dll`, y es a propósito: la buena es la de tu servidor, y un
cliente que no case es peor que ninguno. Apunta `firebird.client_lib` a ella (ver más abajo).

---

<!-- release:drop -->
## Compilación

Para compilar desde el código fuente hacen falta además **Delphi 13 Athens** (RAD Studio 37.0) con
**FireDAC**, y **DMVCFramework** más la biblioteca **`mcp-server-delphi`** clonados en local. Para la
matriz de pruebas, los zip-kits de Firebird que hay bajo `fb_versions/` y Python 3 con `pytest`.

Rutas de búsqueda que el proyecto espera (se configuran una vez en `app/MCPFirebird.dproj`):

```
C:\DEV\mcp-server-delphi\sources
<DMVCFramework>\sources   (every sources subfolder DMVC needs)
C:\DEV\mcp-firebird\sources
C:\DEV\mcp-firebird\providers
```

Compila la aplicación Win64 Debug desde la raíz del repositorio:

```powershell
cmd /c _build_app.bat
```

`_build_app.bat` llama a `rsvars.bat` y luego a `msbuild app\MCPFirebird.dproj /t:Clean;Build /p:Config=Debug /p:Platform=Win64`.
El ejecutable aparece en **`bin\MCPFirebird.exe`**.

(Hay un `_build_core.bat` equivalente para el proyecto de pruebas DUnitX.)

---

## Configuración (`.env`)

Por defecto el servidor lee su configuración de un **fichero `.env` que esté en la misma carpeta que
el ejecutable**, así que dónde ponerlo depende de cómo hayas obtenido el exe:

| | exe | copia la plantilla con |
|---|---|---|
| release descargada | `MCPFirebird.exe` (la carpeta que descomprimiste) | `Copy-Item .env.example .env` |
| compilado desde el código | `bin\MCPFirebird.exe` | `Copy-Item bin\.env.example bin\.env` |

Luego edítalo. (`.env.example` empieza por punto: ni `ls` ni el Explorador lo muestran si no pides
ver los ficheros ocultos. Está en el zip.)

### Elegir otra carpeta de configuración: `--env <dir>`

Por defecto el `.env` se lee de la carpeta del propio ejecutable. Pasa **`--env <dir>`** para leerlo
de otra carpeta. El argumento es un **directorio** (la carpeta que *contiene* el `.env`), no el
fichero:

```powershell
MCPFirebird.exe --env C:\configs\prod      # reads C:\configs\prod\.env
MCPFirebird.exe --env=C:\configs\prod      # the --env=<dir> form also works
MCPFirebird.exe --env ..\shared            # relative paths resolve against the working directory
MCPFirebird.exe                            # no argument -> reads <exe folder>\.env
MCPFirebird.exe --env C:\configs\prod\.env # WRONG -> stops with an error (see below)
```

> **`--env` es una carpeta, nunca el fichero `.env`.** Si lo apuntas al fichero (por ejemplo
> `...\prod\.env`) el servidor se niega a arrancar e imprime la corrección por stderr (que los
> clientes MCP muestran en sus logs de servidor), en lugar de arrancar en silencio con una
> configuración vacía:
>
> ```
> MCPFirebird: --env must point at the FOLDER that contains the .env file, not at the file itself.
>   got:      C:\configs\prod\.env
>   use this: C:\configs\prod
> ```

**Cómo llega el argumento al servidor.** Los clientes MCP no pasan por un shell. Lanzan el ejecutable
directamente con un `command` y un **array** `args`, donde cada elemento del array se convierte en un
argumento independiente. No hay, por tanto, entrecomillado de shell del que preocuparse (las rutas
con espacios funcionan), y el directorio se escribe como su propio elemento del array. Dos formas
equivalentes:

| Forma | valor de `args` |
|---|---|
| separada | `["--env", "C:\\configs\\prod"]` |
| unida | `["--env=C:\\configs\\prod"]` |

**Notas sobre rutas (Windows):** en JSON las barras invertidas van **duplicadas**
(`"C:\\configs\\prod"`), o usa barras normales, que Windows acepta y no necesitan escape
(`"C:/configs/prod"`). En los clientes MCP conviene una ruta **absoluta**: el directorio de trabajo
con el que arrancan es impredecible, así que ahí las rutas relativas no son fiables. Cada arranque
registra la carpeta resuelta en `logs\MCPFirebird.NN.mcp.log`:

```
Boot: .env directory "C:\configs\prod" (.env exists=True)
```

> **Nota:** los logs se escriben siempre en una subcarpeta `logs\` junto al **ejecutable** (`logs\` al lado del exe),
> independientemente de `--env`.

#### Pasar `--env` desde cada cliente MCP

**Claude Desktop** (`%APPDATA%\Claude\claude_desktop_config.json`), **Claude Code** (`.mcp.json`),
**Cursor** (`.cursor/mcp.json`) y **VS Code** (`.vscode/mcp.json`) usan todos la misma forma, un
`command` más un array `args`:

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

Claude Code también puede añadirlo desde la CLI:

```powershell
claude mcp add firebird -- "C:\Tools\MCPFirebird\MCPFirebird.exe" --env "C:\configs\prod"
```

**Gemini CLI** (`~/.gemini/settings.json`), misma forma con `mcpServers`:

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

**OpenCode** (`opencode.json`). Ojo a la diferencia: `command` es un **único array** que ya incluye
los argumentos (no hay un campo `args` aparte):

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

#### Servir varias bases de datos con una sola compilación

Registra el **mismo ejecutable** varias veces con carpetas `--env` distintas. Cada carpeta tiene su
propio `.env`:

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

El cliente muestra entonces dos servidores independientes (`firebird-prod`, `firebird-test`), cada
uno conectado a su propia base de datos.

| Clave | Valor por defecto | Significado |
|---|---|---|
| `firebird.host` | `localhost` | Host del servidor (TCP). Para bases de datos remotas, pon el host o la IP reales |
| `firebird.port` | `3050` | Puerto del servidor |
| `firebird.database` | *(vacío)* | Ruta completa (o alias) de la base de datos en el servidor |
| `firebird.user` | `SYSDBA` | Usuario de conexión |
| `firebird.password` | `masterkey` | Contraseña de conexión |
| `firebird.charset` | `UTF8` | Juego de caracteres de la conexión |
| `firebird.client_lib` | *(vacío)* | Ruta completa a la `fbclient.dll` que se cargará |
| `logger.config.file` | `loggerpro.stdio.json` | Configuración del logger a fichero (los logs van solo a fichero; stdout queda como JSON-RPC puro) |

Ejemplo de `.env`:

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

> **¿Por qué un fichero y no variables de entorno pasadas por el cliente?** La estrategia de dotEnv es
> *primero el fichero, luego el entorno*: el `.env` tiene prioridad y las variables de entorno del
> sistema operativo son el respaldo. Configurar por `.env` funciona igual en todos los clientes MCP
> porque se lee de forma relativa al `.exe`, sea cual sea el directorio de trabajo del cliente.
> Mantén este fichero fuera del control de versiones (ya está en `.gitignore`): contiene
> credenciales.

---

## Ejecutar y verificar a mano

El servidor habla JSON-RPC por stdin/stdout. Puedes probarlo sin ningún cliente MCP, canalizándole
líneas JSON. Desde PowerShell:

```powershell
$msgs = @(
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"manual","version":"1"}}}'
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"fb_info","arguments":{}}}'
) -join "`n"
$msgs | & .\MCPFirebird.exe
```

Lo esperado: un resultado de `initialize` que nombra a `mcp-firebird`, un `tools/list` con las 10
herramientas `fb_*` y un `fb_info` que devuelve la `engine_version` real. (Los logs aparecen en
`logs\`; stdout es JSON-RPC puro.)

---

## Instalarlo en tu agente de IA (Claude, Gemini, Cursor, …)

Así es como el servidor llega a un agente de IA: lo **registras** en la configuración del agente y, a
partir de ahí, el agente puede llamar a sus herramientas mientras te responde. No corre ningún
servicio ni escucha en ningún puerto. El agente **arranca el ejecutable él mismo**, como proceso
hijo, y habla con él por stdin/stdout (esto es lo que MCP llama un *servidor stdio*). Cierras el
agente y el servidor se va con él.

Así que la instalación entera consiste en darle al agente **un comando** (la ruta absoluta a
`MCPFirebird.exe`) en el fichero o la CLI que su fabricante ofrezca para eso. Abajo están las recetas
de los agentes más comunes; todas son el mismo comando con otra sintaxis. La conexión a la base de
datos no forma parte de esto: el servidor la lee del `.env` que hay junto al ejecutable (arriba), o
de `--env <dir>`.

### Claude Desktop

Edita `%APPDATA%\Claude\claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe"
    }
  }
}
```

Reinicia Claude Desktop. Las herramientas `fb_*`, los prompts `optimization_goal` / `health_check` y
el recurso `firebird://schema` aparecen en el cliente.

### Claude Code (CLI)

Añádelo con un solo comando (servidor stdio local):

```powershell
claude mcp add firebird -- "C:\Tools\MCPFirebird\MCPFirebird.exe"
```

O sube al repositorio un `.mcp.json` de proyecto en la raíz, para que tus compañeros lo hereden:

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

Compruébalo con `claude mcp list` (o con `/mcp` dentro de una sesión).

### Gemini CLI

Edita `~/.gemini/settings.json` (o un `.gemini/settings.json` de proyecto):

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

Después, `/mcp` dentro de Gemini CLI lista el servidor y sus herramientas. Poner `cwd` en la carpeta
del exe mantiene ordenado el directorio `logs\` (el `.env` se localiza por la ruta del exe en
cualquier caso).

### OpenCode

Edita `opencode.json` (el global `~/.config/opencode/opencode.json` o el de proyecto) y registra un
servidor MCP **local** (`command` es un array argv):

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

Cursor lee `.cursor/mcp.json`; VS Code (y las extensiones que entienden MCP) leen `.vscode/mcp.json`.
Los dos usan la misma forma:

```json
{
  "mcpServers": {
    "firebird": {
      "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe"
    }
  }
}
```

### Cualquier otro cliente MCP

El servidor es un servidor MCP **stdio** estándar. Sea cual sea el formato de configuración del
cliente, dale:

- **command:** `C:\Tools\MCPFirebird\MCPFirebird.exe`
- **args:** *(ninguno)*, o `["--env", "C:\\configs\\prod"]` para usar un `.env` de otra carpeta
- **transport:** stdio
- **env:** *(no hace falta ninguno)*, la conexión sale del `.env`

> **Truco:** para que distintos clientes apunten a distintas bases de datos, dale a cada uno un
> `--env <dir>` diferente (una carpeta con su propio `.env`). No hace falta duplicar toda la carpeta
> de instalación. Por ejemplo, en un `.mcp.json` de Claude Code:
> ```json
> { "mcpServers": { "firebird": {
>     "command": "C:\\Tools\\MCPFirebird\\MCPFirebird.exe",
>     "args": ["--env", "C:\\configs\\prod"] } } }
> ```

---

## Usarlo desde Claude

Con el servidor registrado, le hablas a Claude en lenguaje llano. Él elige la herramienta `fb_*`
adecuada, la ejecuta contra la base de datos que configuraste y convierte el resultado en SQL listo
para ejecutar. Los intercambios de abajo dan por hecha la base de datos de demostración; cambia los
nombres de tablas y columnas por los tuyos.

> En **Claude Desktop** las herramientas aparecen solas y los dos prompts salen como comandos (el
> menú 🔌 / "+"). En **Claude Code**, `/mcp` inspecciona el servidor y los prompts están disponibles
> como comandos de barra. Siempre puedes empujarlo de forma explícita: *"usa las herramientas de
> firebird"*.

### 1. Situarte

> **Tú:** ¿A qué versión de Firebird estoy conectado y qué funciones hay disponibles?

Claude llama a **`fb_info`** e informa de la versión del motor, el dialecto, el charset y las
capacidades detectadas (tablas MON$, planes explicados, BOOLEAN, INT128, zonas horarias, workers
paralelos).

> **Tú:** Lista las tablas de la base de datos.

→ **`fb_list_tables`** → `CUSTOMERS`, `ORDERS`, `NOPK_LOG`, `OVERIDX`, `STALE_T`, …

### 2. Documentar un esquema

> **Tú:** Documenta la tabla CUSTOMERS.

→ **`fb_generate_documentation`** → columnas, la clave primaria `CUSTOMER_ID` y los índices.

> **Tú:** Genera la documentación Markdown completa de toda la base de datos y guárdala en un
> fichero.

→ **`fb_generate_documentation`** otra vez (sin tabla = base de datos entera). Claude devuelve el
Markdown; pídele que guarde el texto en `docs/schema.md` si lo quieres en disco.

### 3. Diagnosticar una query lenta y arreglarla

> **Tú:** Esta query va lenta, ¿por qué?
> `SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'`

→ **`fb_analyze_query`** → *"⚠️ Escaneo NATURAL sobre CUSTOMERS: la columna filtrada `CITY` no tiene
un índice útil."*

> **Tú:** Propón un índice que lo arregle.

→ **`fb_suggest_indexes`** → una sentencia lista para ejecutar y cómo verificarla:

```sql
CREATE INDEX IDX_CUSTOMERS_CITY ON CUSTOMERS (CITY);
-- Verify: re-run fb_analyze_query; the NATURAL scan on CUSTOMERS should be gone.
```

> **Tú:** ¿Y esta? `SELECT * FROM CUSTOMERS ORDER BY CITY`

→ **`fb_analyze_query`** señala un **SORT externo** (no hay ningún índice que sirva para ese orden).

### 4. Limpiar índices redundantes

> **Tú:** ¿Qué índices de ORDERS puedo borrar sin riesgo?

→ **`fb_suggest_index_drops`** → marca `IDX_ORDERS_CUSTOMER_DUP` como duplicado del índice de sistema
de la clave foránea, con la sentencia `DROP INDEX` y un paso de verificación.

> **Tú:** Haz lo mismo con CUSTOMERS.

→ marca el prefijo izquierdo redundante (`IDX_CUST_NAME`), el índice inactivo (`IDX_CUST_CITY`) y el
índice de baja selectividad (`IDX_CUST_STATUS`).

### 5. Auditar la salud del esquema

> **Tú:** Audita la tabla NOPK_LOG.

→ **`fb_audit_table`** → *"🛑 crítico: la tabla NOPK_LOG no tiene PRIMARY KEY …"* con la corrección
`ALTER TABLE … ADD CONSTRAINT`. En `OVERIDX` informa de exceso de índices; en `STALE_T`, de
estadísticas obsoletas, con la corrección `SET STATISTICS INDEX …`.

> **Tú:** Haz una revisión completa de salud de la base de datos.

→ Claude usa el prompt **`health_check`**: `fb_info` → `fb_list_tables` → `fb_suggest_index_drops` por
tabla → un único resumen agrupado por tabla con todo el SQL listo para ejecutar.

### 6. Optimización por objetivos (iterar hasta cumplirlo)

El prompt **`optimization_goal`** hace que Claude entre en bucle: medir → proponer → volver a medir, y
se detiene en cuanto el objetivo se cumple (o ya no puede mejorarlo).

> **Tú:** Usa el prompt optimization_goal. Sigue optimizando hasta que esta query deje de hacer un
> escaneo natural:
> `SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'`

Claude:
1. Llama a **`fb_evaluate_goal`** (`goal_type=query_no_natural_scan`) → `met: false` (línea base).
2. Llama a `fb_analyze_query` y a `fb_suggest_indexes`, y presenta `CREATE INDEX IDX_CUSTOMERS_CITY …`.
3. Tú ejecutas el SQL (las escrituras están desactivadas por defecto, ver [Seguridad](#seguridad-y-compatibilidad)).
4. Vuelve a llamar a `fb_evaluate_goal` → `met: true`, y se detiene con el resultado.

También puedes fijar el objetivo con un número, por ejemplo *"baja esta query de 50 ms"*
(`goal_type=query_time_ms`, `threshold=50`).

---

## Sesión real: optimizar una query sobre `employee.fdb`

Un recorrido completo sobre la base de datos de ejemplo **`employee`** que viene con Firebird
(`examples/empbuild/employee.fdb`). Las salidas de abajo son literales de las herramientas.

> **Tú:** Analiza esta query de Firebird y sugiere mejoras:
> ```sql
> SELECT emp_no, first_name, last_name, salary
> FROM employee
> WHERE salary > 60000
> ```

**1. Línea base.** `fb_analyze_query` devuelve (motor `3.0.12`):

```
PLAN (EMPLOYEE NATURAL)
```
> Escaneo NATURAL sobre: EMPLOYEE. Ejecuta `fb_suggest_indexes` con esta query para obtener el DDL listo para ejecutar.

`NATURAL` significa que Firebird lee **todas** las filas de `EMPLOYEE` y descarta las que tienen
`salary <= 60000`: no hay ningún índice sobre `SALARY` por el que buscar.

**2. Confirmar el problema.** `fb_evaluate_goal` (`goal_type=query_no_natural_scan`):

```json
{ "goal_type": "query_no_natural_scan", "measured": 1.0, "met": false,
  "iteration_hint": "plan: PLAN (EMPLOYEE NATURAL)", "engine_version": "3.0.12" }
```

**3. Obtener la corrección.** `fb_suggest_indexes`:

```sql
CREATE INDEX IDX_EMPLOYEE_SALARY ON EMPLOYEE (salary);
```
> **Verify:** vuelve a ejecutar `fb_analyze_query`; el plan debería usar `IDX_EMPLOYEE_SALARY` y ya no
> mostrar `EMPLOYEE NATURAL`. Después ejecuta `SET STATISTICS INDEX IDX_EMPLOYEE_SALARY;` para
> refrescar la selectividad.

**4. Aplicarla** (el servidor es de solo lectura: el DDL lo ejecutas tú) y **volver a analizar**: el plan pasa a ser `PLAN (EMPLOYEE INDEX (IDX_EMPLOYEE_SALARY))` y
`fb_evaluate_goal` devuelve `met: true`.

**Cuándo *no* conviene añadir el índice.** La ganancia viene de que `salary > 60000` sea
**selectivo** (pocas filas). Si el predicado casara con casi toda la tabla (por ejemplo
`salary > 0`), el escaneo NATURAL sería en realidad el plan más barato y el índice solo añadiría
coste de escritura. No todo escaneo NATURAL es un error.

---

## Referencia de herramientas

Unos cuantos ejemplos de llamada (los `arguments` de un `tools/call` MCP):

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

Valores de `goal_type` que `fb_evaluate_goal` admite en M1: `query_no_natural_scan`,
`query_time_ms`, `no_redundant_indexes`. En
[`docs/firebird-problem-catalog.md`](docs/firebird-problem-catalog.md) están todos los problemas que
detectan las herramientas, el fixture que provoca cada uno y el milestone en el que entra.

### Herramientas Enterprise

Estas nueve aparecen también en el `tools/list` de aquí, para que tu asistente sepa que existen y
pueda decirte qué haría con ellas. Llamarlas en esta edición devuelve un resultado `isError` que
explica cómo conseguirlas. Están implementadas en la [edición Enterprise](#edición-enterprise), que se
conecta al Services Manager como administrador y lee la configuración y el hardware del servidor:
privilegios que esta edición no pide nunca.

| Herramienta | Argumentos | Qué hace |
|---|---|---|
| `fb_diagnose` | *(ninguno)* | Empieza aquí cuando algo va mal y no sabes por qué: lo que ya se sabe, qué preguntar, y la ruta a seguir |
| `fb_analyze_config` | *(ninguno)* | Lee `firebird.conf` y `databases.conf` e informa de todos los ajustes que importan (page buffers, `TempCacheLimit`, `LockHashSlots`, `MaxUnflushedWrites`, `GCPolicy`, workers paralelos) contra *esta* versión del motor y *esta* arquitectura de servidor, porque los valores por defecto, y hasta la existencia misma de un parámetro, cambian con ambas |
| `fb_analyze_storage` | `table_name?` | La foto física que ningún `SELECT` puede dar: profundidad de los índices, grado de llenado de las páginas, longitud de las cadenas de versiones de registro, distribución de páginas |
| `fb_parse_log` | *(ninguno)* | Transmite `firebird.log` por la API de Servicios y separa el ruido de lo que importa: bugchecks, corrupción de páginas, errores de E/S, sweeps que se ejecutaron, o que nunca llegaron a hacerlo |
| `fb_capture_trace` | *(ninguno)* | Abre una sesión acotada de la Trace API, muestrea la carga real y ordena las sentencias que de verdad cuestan, como distribución de latencia y no como media |
| `fb_trace_start` | `duration_seconds?` | Abre la ventana larga: hasta dos horas de captura por la Trace API, drenadas a disco en segundo plano mientras la llamada vuelve al instante |
| `fb_trace_status` | *(ninguno)* | Informa de la captura en curso: tiempo transcurrido contra duración, bytes capturados, y si la sesión sigue observando |
| `fb_trace_stop` | *(ninguno)* | Detiene la captura, o recupera una ya terminada, y devuelve el mismo informe ordenado que `fb_capture_trace`, sobre horas en vez de segundos |
| `fb_analyze_host` | `config_dir?` | El motor frente a su hardware: la RAM contra la memoria que la configuración compromete de verdad, el número de núcleos contra `MaxParallelWorkers` y `CpuAffinityMask`, el espacio libre contra el tamaño de la base de datos, y si las páginas que falla le cuestan un seek |

Y además lo que las convierte en producto y no en un informe: **líneas base y experimentos.** Toma una
medida bajo carga real, cambia un parámetro, toma otra, y obtén un veredicto sobre si la cola de la
distribución se movió, con vuelta atrás si no lo hizo.

La documentación de Firebird no fija un valor óptimo para la mayoría de estos parámetros, y nosotros
tampoco lo haremos. Lo que aporta la edición Enterprise es el mapa que va del síntoma al parámetro que
lo explica, y un banco de pruebas que demuestra que el cambio funcionó en tu base de datos.

---

<!-- release:drop -->
## Probar el proyecto

La batería ejecuta las **pruebas de núcleo DUnitX contra servidores Firebird reales** (de 2.5 a 5.0),
más una **batería de conformidad stdio en Python** y una **comprobación de la frontera del núcleo**.

### Requisitos de la matriz de pruebas

- Los zip-kits de Firebird presentes en `fb_versions/` (rutas y puertos en
  `tests/fbkit.versions.psd1`). Puertos: **2.5 → 3070**, 3.0 → 3053, 4.0 → 3054, 5.0 → 3055.
- **Una sola vez** por kit: los zip-kits vienen sin un `SYSDBA` utilizable. Con el servidor parado,
  créalo en modo embebido (hace falta en 3.0/4.0/5.0; 2.5 funciona tal cual):
  ```
  <kit>\isql.exe -user SYSDBA "<kit>\security<N>.fdb"
    CREATE USER SYSDBA PASSWORD 'masterkey';
    COMMIT; QUIT;
  ```
  (`security3.fdb` / `security4.fdb` / `security5.fdb`).
- Python 3 con `pytest` (`python -m pip install pytest`).

### Ejecutarlo todo (un solo comando)

```powershell
pwsh tests/run_all.ps1
```

#### O con PyInvoke (`tasks.py`)

Un `tasks.py` envuelve todo el flujo de compilación y pruebas (`python -m pip install invoke`):

```powershell
invoke --list                 # show all tasks
invoke build                  # build the core test project + the MCP app
invoke core --version 5.0     # core suite against one FB version (start/seed/test/stop)
invoke matrix                 # core suite across every present FB version
invoke compliance             # Python stdio MCP compliance suite (on FB 5.0)
invoke boundary               # enforce the core/MVCFramework boundary
invoke all                    # full run_all.ps1 (matrix + boundary + compliance)
```

Para cada kit presente: arranca el servidor → siembra un `TESTDB.FDB` nuevo → ejecuta el exe de núcleo
→ para el servidor; luego lanza la comprobación de frontera y la batería de Python sobre 5.0. Final
esperado:

```
==== Core suite on FB 2.5 ====   ... 27 passed / 3 ignored
==== Core suite on FB 3.0 ====   ... 27 passed / 3 ignored
==== Core suite on FB 4.0 ====   ... 27 passed / 3 ignored
==== Core suite on FB 5.0 ====   ... 27 passed / 3 ignored
Core boundary OK: no MVCFramework imports in sources/
7 passed
ALL SUITES PASSED
```

(Las 3 pruebas *ignored* son detectores pendientes de M2, que se dejan a la vista como backlog.)

### Ejecutar contra una sola versión

```powershell
pwsh tests/fbkit.ps1   -Action start  -Version 5.0
pwsh tests/seed/make_seed.ps1          -Version 5.0
$env:FBTEST_PORT='3055'
$env:FBTEST_DB='C:\DEV\mcp-firebird\tests\seed\TESTDB.FDB'
$env:FBTEST_CLIENTLIB=(pwsh tests/fbkit.ps1 -Action client -Version 5.0)
& 'C:\DEV\mcp-firebird\tests\coreproject\MCPFirebirdCoreTests.exe'
pwsh tests/fbkit.ps1   -Action stop   -Version 5.0
```

### Solo la conformidad en Python

```powershell
pwsh tests/fbkit.ps1 -Action start -Version 5.0
pwsh tests/seed/make_seed.ps1 -Version 5.0
python -m pytest tests/test_mcp_firebird_stdio.py -v
pwsh tests/fbkit.ps1 -Action stop -Version 5.0
```

---

## Resolución de problemas

| Síntoma | Causa probable y solución |
|---|---|
| El cliente muestra el servidor pero **ninguna herramienta** | Falta el `.env`, o la base de datos no es accesible: el servidor arranca, pero las herramientas fallan al conectar. Pruébalo con la [prueba manual](#ejecutar-y-verificar-a-mano). |
| `Your user name and password are not defined` (SQLSTATE 28000) | Credenciales incorrectas, o un zip-kit sin `SYSDBA`. Ver la inicialización de una sola vez, más arriba. |
| Las herramientas de análisis no devuelven nada, o ningún escaneo NATURAL, en una base de datos **remota** | Asegúrate de que `firebird.host` es el host real (el analizador de planes usa el host configurado). |
| No encuentra `fbclient.dll`, o es de otra arquitectura | Pon en `firebird.client_lib` una `fbclient.dll` de **Win64**; un cliente 5.0 funciona contra servidores de 2.5 a 5.0. |
| Aparece ruido no JSON en stdout | El log tiene que ir solo a fichero: mantén `logger.config.file=loggerpro.stdio.json`. |
| El puerto 3050 ya lo ocupa otro Firebird | Usa un puerto distinto (por eso el banco de pruebas pone FB 2.5 en el **3070**). |

---

## Seguridad y compatibilidad

- **Solo lectura.** Ninguna herramienta ejecuta DDL ni SQL de escritura. El SQL que te entrega una
  recomendación lo ejecutas tú, cuando y si lo decides. Están previstas herramientas que apliquen el
  cambio por su cuenta y, cuando lleguen, vendrán desactivadas hasta que tú las actives.
- **Multiversión.** La detección de capacidades adapta el uso de las funciones (tablas MON$, planes
  explicados, BOOLEAN, INT128, zonas horarias, workers paralelos) al motor conectado; validado en FB
  2.5 / 3.0 / 4.0 / 5.0.
- **Una sola base de datos configurada** por instancia del servidor (si necesitas varias, ejecuta
  varias instancias).

---

## Licencia

Desde la **v0.2.0**, la licencia es la **[PolyForm Internal Use License 1.0.0](LICENSE)**: gratuito
en tus propias bases de datos, a cualquier escala, y solo necesitas licencia para entregarle el
software a otra persona. Lo que eso significa en la práctica está en
[Ediciones y licencias](#ediciones-y-licencias); ver también [`NOTICE`](NOTICE).

**La v0.1.0 y las anteriores salieron bajo Apache-2.0, y bajo Apache-2.0 siguen** para quien las
recibió.

MCP Firebird es un escaparate de
[mcp-server-delphi](https://github.com/danieleteti/mcp-server-delphi). Si vas a construir tu propio
servidor MCP en Delphi, empieza por ahí.
