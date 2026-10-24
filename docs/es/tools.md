# Referencia de herramientas

[← volver al README](../../README-ES.md)

El catálogo completo: qué hace cada herramienta, cómo decide el asesor de índices, los
prompts y el recurso, más las llamadas `tools/call` en crudo si pilotas el servidor tú.

## Las herramientas (16 gratuitas, más 9 Enterprise anunciadas en `tools/list`)

| Herramienta | Argumentos | Para qué sirve |
|---|---|---|
| `fb_info` | *(ninguno)* | Versión del motor y capacidades detectadas (JSON) |
| `fb_list_tables` | *(ninguno)* | Lista las tablas de usuario |
| `fb_generate_documentation` | `table_name?` | Documentación Markdown de una tabla — columnas (con el **dominio** en el que se apoyan), PK, índices, **restricciones CHECK**, triggers con el evento que los dispara — o de toda la base de datos, que además lista las **vistas con su SELECT**, los procedimientos con sus parámetros, las funciones y los paquetes (3.0+). Si el nombre es el de una vista, documenta la vista |
| `fb_query` | `sql`, `max_rows?` | Ejecuta un SELECT de solo lectura y devuelve las filas como tabla Markdown, con un tope de `max_rows` (por defecto 100, máximo 1000) **y de ~20 000 caracteres**, porque un tope de filas limita filas y no anchura. Se rechaza todo lo que no sea un SELECT simple, y también una sentencia con marcadores sin rellenar |
| `fb_analyze_query` | `sql` | Análisis del plan de acceso (escaneos NATURAL y SORT externos), el **plan explicado** del motor en 3.0+ (nombres de índices, qué parte del índice usó la consulta, estrategia de join) **y coste medido**: un SELECT simple se ejecuta una vez y se informan los registros y las páginas que realmente tocó |
| `fb_suggest_indexes` | `sql` | Aconseja el índice para una consulta: B-tree normal, **de expresión** (`COMPUTED BY`), **parcial** (5.0+) o un índice para la **ordenación** — y **ningún índice** cuando el escaneo es el plan correcto. Antes de proponer algo estructural refresca las estadísticas obsoletas |
| `fb_suggest_index_drops` | `table_name` | Señala índices duplicados, con prefijo redundante, inactivos o de baja selectividad |
| `fb_audit_table` | `table_name` | Auditoría de salud del esquema: PK ausente, exceso de índices, estadísticas obsoletas |
| `fb_suggest_grants` | `user_name`, `object_pattern?`, `access?`, `role_name?`, `exclude_pattern?` | Las sentencias que dan a una cuenta acceso a los objetos que casan con un patrón **y a nada más**: un `CREATE USER` condicional, un rol, los `GRANT` generados desde el catálogo con los identificadores entrecomillados solo donde Firebird lo exige, y el rol concedido en la forma que admite esta versión (`GRANT DEFAULT` desde 4.0; por debajo, la nota de que la conexión debe pasar el rol o los permisos no sirven de nada). Después comprueba la afirmación: los permisos de PUBLIC y los que la cuenta ya tiene fuera del plan vuelven como hallazgos, con el `REVOKE` que los cierra |
| `fb_audit_security` | `user_name?` | Todos los permisos registrados en la base de datos, una línea por beneficiario y objeto, más los tres hallazgos que suelen ser un error: privilegios en manos de **PUBLIC** (critical si incluyen escritura), delegación con **WITH GRANT OPTION** y roles sin ningún miembro |
| `fb_evaluate_goal` | `goal_type`, `target`, `threshold` | Comprobación determinista del objetivo (es lo que mueve el bucle de optimización) |
| `fb_monitor_transactions` | `stale_minutes?` | Salud de transacciones y sweep **en este instante**: distancia OIT/OAT/Next, transacciones largas que bloquean (con su última sentencia SQL) |
| `fb_sample_activity` | `seconds?` | Lee los contadores MON$ dos veces a lo largo de una ventana e informa la diferencia: registros leídos en secuencia y por índice, páginas movidas, versiones recogidas, y si el horizonte de transacciones avanzó |
| `fb_monitor_attachments` | `idle_minutes?`, `long_statement_seconds?` | Quién está conectado ahora, desde dónde y qué está ejecutando; marca las conexiones inactivas más de `idle_minutes` (por defecto 30) y las sentencias que llevan más de `long_statement_seconds` (por defecto 60). No ve la contención: MON$ cuenta el trabajo hecho, nunca el tiempo esperando permiso para hacerlo |
| `fb_backup_start` | *(ninguno)* | Lanza un backup `gbak` dentro de `firebird.backup_dir` y **vuelve antes de que el backup termine**. Después el job restaura lo que escribió en una base de datos desechable y la borra |
| `fb_backup_status` | *(ninguno)* | El backup en curso o el último: fase, tamaño, cuánto duró cada etapa, y si se demostró que el backup se puede restaurar |

### Qué necesita el backup, y qué demuestra

Un backup que nadie ha restaurado es un fichero, no un backup. Por eso el job no se detiene al
escribir el `.fbk`: lo restaura en una base de datos desechable con `gbak -c` (que *crea*, y rechaza
un fichero que ya exista), comprueba que la base de datos llegó, y la tira. `fb_backup_status` dice
*«este backup se restaura»*, no *«existe un fichero»*.

Necesita tres cosas, todas de tu parte:

- **`firebird.backup_dir`** en el `.env`. El destino se declara una sola vez, ahí, y nunca lo pone
  quien llama: las herramientas reciben instrucciones de cualquiera que hable con el servidor.
- **`gbak.exe` junto a tu `fbclient.dll`.** El servidor pilota una herramienta cliente *local*. Nunca se conecta al Services Manager.
- **Sitio para una segunda copia de la base de datos** en ese disco, mientras dure la restauración
  de verificación.

Un backup a la vez: `fb_backup_start` se niega mientras hay uno en marcha y te dice que hagas
polling. Y lo que no puede decirte: si el backup está **fuera de esta máquina**. Un backup que se
demuestra restaurable, pero que vive en el mismo disco que la base de datos de la que salió,
sobrevive a una página corrupta, no a la pérdida del disco.

Cada recomendación viene con un **Finding**, el **SQL** listo para ejecutar y un paso de
**Verify**. Cada herramienta de análisis termina además declarando **qué no ha descartado**:
un plan no ve la contención, una instantánea no ve la acumulación, y una respuesta limpia a
una pregunta estrecha no es un certificado de buena salud.

## Qué decide `fb_suggest_indexes`, y en qué orden

Un índice no es gratis: se escribe en cada INSERT, UPDATE y DELETE sobre esa tabla, mientras
exista. Por eso el consejero propone **el remedio más barato que explique lo que hizo el plan**, y
está dispuesto a no proponer nada.

1. **Refrescar, no construir.** Firebird guarda la selectividad de un índice cuando el índice se
   crea y nunca la recalcula. Un índice que existe y se ignora puede estar ignorándose porque el
   optimizador lo está evaluando sobre los datos del año pasado — y responder a eso con un segundo
   índice deja a la base de datos pagando escrituras para siempre porque un número necesitaba una
   actualización. Aquí nadie dice *"el índice no se usa, y está bien así"* hasta que la cifra
   almacenada se ha comparado con la real.
2. **Despertar, no duplicar.** Un índice `INACTIVE` sobre la columna filtrada es
   `ALTER INDEX … ACTIVE`, nunca un segundo índice al lado del que duerme.
3. **Decir cuándo el escaneo es lo correcto.** La consulta se ejecuta una vez y los registros
   leídos se comparan con las filas devueltas. Un escaneo que se queda con casi todo lo que lee
   *es* el plan correcto, y también lo es el de una tabla que cabe en un puñado de páginas: ambos
   vuelven como un hallazgo con las cifras y **sin SQL que ejecutar**.
4. **Y entonces, la forma adecuada.** `UPPER(NOMBRE) = ?` no puede usar ningún índice normal y
   recibe un índice de expresión, con la expresión emitida exactamente como estaba escrita —
   Firebird solo lo usa si coincide exactamente. `ESTADO = 'ACTIVO' AND TAG = ?` recibe el índice
   sobre la columna por la que se busca, más la forma parcial en 5.0+, que indexa solo la
   población que la consulta mira. Un `ORDER BY` sobre una columna sin índice recibe un índice
   cuyos segmentos coinciden con la ordenación **en su propia dirección** — y la constatación de
   que ningún índice sirve para `ORDER BY a ASC, b DESC`, en lugar de uno que no se usaría.

Cada hallazgo lleva las cifras a las que se aplicó la regla, de modo que un DBA que no esté de
acuerdo con un umbral pueda discutir el umbral y no la herramienta. El diseño y las mediciones en
que se apoya están en
[`docs/superpowers/specs/2026-08-07-index-advisor.md`](../superpowers/specs/2026-08-07-index-advisor.md).

> **Nota:** para medir, esta herramienta **ejecuta la consulta** sobre la que se le pregunta —
> una vez, dentro de la transacción de solo lectura, y solo cuando el plan muestra realmente un
> escaneo o una ordenación. En una tabla grande eso es un escaneo completo. Nunca ejecuta nada que
> no sea un SELECT simple, y no ejecuta en absoluto una sentencia con parámetros sin valor: llegan
> al motor como NULL, no casan con nada y producirían la medición de una consulta que nadie
> ejecuta.

## Qué ve `fb_audit_security` y qué no puede ver

Los permisos viven en la base de datos: `RDB$USER_PRIVILEGES` y `RDB$ROLES`, legibles desde una
conexión SQL normal — que es exactamente lo que es la edición gratuita. El informe es completo
sobre *permisos*, y calla sobre todo lo que un permiso no es. Quedan fuera dos clases de fila,
porque nadie las concedió y listarlas entierra las que sí concedió alguien: los privilegios
propios del motor sobre `RDB$`/`MON$` y los que cada propietario tiene sobre sus objetos.

No ve la **lista de cuentas**, ni los **roles administrativos**, ni la política de contraseñas, ni
quién llega siquiera al puerto: eso vive en la base de datos de seguridad y en la configuración
del servidor, y leerlo exige un attach administrativo que esta edición no hace. Una base de datos
con todos los permisos correctos puede seguir siendo accesible por una cuenta que nadie recuerda
haber creado.

Con `user_name` responde a la otra pregunta: **qué alcanza esa cuenta y por qué vía** — concedido
a ella directamente, concedido a PUBLIC o concedido a un rol del que es miembro. Una fila que llega
por un rol lleva la marca *(only when active)*, porque en Firebird un rol está inactivo mientras la
conexión no lo nombre o no se haya concedido como rol DEFAULT (4.0+) — y cuál de las dos cosas
aplica está en la base de datos de seguridad, donde este servidor no mira. El informe también avisa
cuando la cuenta es SYSDBA o es propietaria de objetos, porque ninguna de las dos está sujeta a los
permisos listados.

Tres hallazgos, en el orden en que importan:

1. **PUBLIC.** No es un grupo al que alguien se haya apuntado: es todo el que pueda conectarse,
   incluidas las cuentas creadas después de conceder el permiso. `critical` si incluye INSERT,
   UPDATE o DELETE; `warning` en caso contrario.
2. **WITH GRANT OPTION.** Quien lo tiene puede ampliar el acceso sin que ningún DBA lo vea, y el
   permiso resultante es indistinguible de uno hecho por un administrador.
3. **Un rol sin miembros.** O los privilegios que lleva no se usan, o las cuentas que deberían
   tenerlos están usando permisos directos.

## Prompts (4)

- **`optimization_goal`**, el bucle guiado por objetivos: fija una meta y el asistente itera sobre
  las herramientas `fb_*` y vuelve a comprobar `fb_evaluate_goal` hasta que devuelve `met: true`
  (con una parada de seguridad por máximo de iteraciones o por falta de progreso).
- **`app_user_plan`**: el único prompt que parte de una decisión que nadie ha tomado todavía. La
  mayoría de las aplicaciones Firebird se conectan como SYSDBA, y eso no es un problema de
  permisos: es una base de datos donde los permisos no se aplican, porque SYSDBA no está sujeto a
  ellos y el propietario de un objeto tampoco. Así que el prompt mira primero (versión del motor,
  nombres de los objetos, qué tiene ya PUBLIC), pregunta solo lo que el catálogo no sabe y acaba
  en `fb_suggest_grants` en vez de en GRANTs inventados. Si no llegan las respuestas no se
  atasca: ofrece el plan de repliegue, porque una cuenta con DML sobre todas las tablas sigue sin
  poder borrar una tabla, cambiar el esquema, leer la base de datos de seguridad, crear cuentas o
  parar el servidor.
- **`health_check`**: revisión guiada de la salud de toda la base de datos — los índices tabla
  por tabla, luego los permisos de una sola pasada, diciendo dónde se detiene esa parte.
- **`classify_problem`**: parte del síntoma, no de una herramienta. Sitúa el problema en seis
  ejes (forma temporal, volumen frente a concurrencia, localidad, coordinación frente a
  ejecución, sensibilidad a la observación, entorno), nombra la clase dominante de las siete
  y dice qué razonamiento converge — incluso cuando la respuesta es que una conexión SQL no
  puede zanjarlo. Sigue la taxonomía de Cisar y Reeves, *Practical Firebird Performance
  Diagnostics* (IBPhoenix, 2026).

## Recursos (1)

- **`firebird://schema`**: el esquema vivo de la base de datos como un único recurso.

## Llamar a las herramientas directamente

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

// Qué cambió en los últimos 10 segundos (una ventana, no un instante)
{ "name": "fb_sample_activity", "arguments": { "seconds": 10 } }

// Goal check: "this query must no longer do a NATURAL scan"
{ "name": "fb_evaluate_goal",
  "arguments": { "goal_type": "query_no_natural_scan",
                 "target": "SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'",
                 "threshold": 0 } }
```

Valores de `goal_type` que `fb_evaluate_goal` admite en M1: `query_no_natural_scan`,
`query_time_ms`, `no_redundant_indexes` y `no_stale_index_statistics` — el único cuya primera
jugada no escribe nada estructural: cuenta los índices de una tabla cuya selectividad almacenada
ya no describe los datos, para que el bucle pueda decirle la verdad al optimizador antes de pedirle
a la base de datos que cargue con otro índice. En
[`docs/firebird-problem-catalog.md`](../firebird-problem-catalog.md) están todos los problemas que
detectan las herramientas, el fixture que provoca cada uno y el milestone en el que entra.

## Herramientas Enterprise

Estas nueve aparecen también en el `tools/list` de aquí, para que tu asistente sepa que existen y
pueda decirte qué haría con ellas. Llamarlas en esta edición devuelve un resultado `isError` que
explica cómo conseguirlas. Están implementadas en la [edición Enterprise](editions.md#edición-enterprise), que se
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
