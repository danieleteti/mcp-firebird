# Instalación, configuración, registro

[← volver al README](../../README-ES.md)

Todo lo necesario para ponerlo en marcha: requisitos, el `.env` que lee, cómo apuntar
varias instalaciones a varias bases de datos, y el fragmento exacto para cada cliente MCP.

## Requisitos

- **Windows x64** (el servidor es una aplicación de consola nativa Win64).
- Una **biblioteca cliente de Firebird** (`fbclient.dll`) igual o más reciente que el servidor al que
  apuntas. Una `fbclient.dll` de 5.0 conecta sin problemas con servidores de 2.5 a 5.0.
- Una **base de datos Firebird** accesible a la que apuntar.

La descarga no incluye ninguna `fbclient.dll`, y es a propósito: la buena es la de tu servidor, y un
cliente que no case es peor que ninguno. Apunta `firebird.client_lib` a ella (ver más abajo).

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

Reinicia Claude Desktop. Las herramientas `fb_*`, los prompts `optimization_goal` / `health_check` / `classify_problem` y
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
