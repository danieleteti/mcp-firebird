# Ejemplos reales

[← volver al README](../../README-ES.md)

Cómo es la conversación de verdad una vez registrado el servidor, desde «qué tablas
tengo» hasta una vuelta completa de optimización sobre `employee.fdb`.

## Usarlo desde Claude

Con el servidor registrado, le hablas a Claude en lenguaje llano. Él elige la herramienta `fb_*`
adecuada, la ejecuta contra la base de datos que configuraste y convierte el resultado en SQL listo
para ejecutar. Los intercambios de abajo dan por hecha la base de datos de demostración; cambia los
nombres de tablas y columnas por los tuyos.

> En **Claude Desktop** las herramientas aparecen solas y los tres prompts salen como comandos (el
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
tabla → `fb_audit_security` una vez → un resumen en dos partes: el SQL de los índices agrupado por
tabla y luego los hallazgos de permisos, los critical primero.

### 6. Optimización por objetivos (iterar hasta cumplirlo)

El prompt **`optimization_goal`** hace que Claude entre en bucle: medir → proponer → volver a medir, y
se detiene en cuanto el objetivo se cumple (o ya no puede mejorarlo).

> **Tú:** Usa el prompt optimization_goal. Sigue optimizando hasta que esta query deje de hacer un
> escaneo natural:
> `SELECT * FROM CUSTOMERS WHERE CITY = 'Rome'`

Claude:
1. Llama a **`fb_evaluate_goal`** (`goal_type=query_no_natural_scan`) → `met: false` (línea base).
2. Llama a `fb_analyze_query` y a `fb_suggest_indexes`, y presenta `CREATE INDEX IDX_CUSTOMERS_CITY …`.
3. Tú ejecutas el SQL (las escrituras están desactivadas por defecto, ver [Seguridad](../../README-ES.md#seguridad-y-compatibilidad)).
4. Vuelve a llamar a `fb_evaluate_goal` → `met: true`, y se detiene con el resultado.

También puedes fijar el objetivo con un número, por ejemplo *"baja esta query de 50 ms"*
(`goal_type=query_time_ms`, `threshold=50`).

---

### 7. "¿Está empeorando, o siempre fue así?"

Hay problemas que no están en ninguna consulta. Se acumulan.

> **Tú:** La pantalla de pedidos se arrastra cada tarde y nadie ha tocado nada. Usa el prompt
> classify_problem.

→ **`classify_problem`** sitúa el síntoma en seis ejes antes de tocar una herramienta: si crece a lo
largo de horas o aparece al instante bajo carga, si sigue al volumen o a la concurrencia, si se
concentra en unas pocas tablas, si el tiempo se va trabajando o esperando. Después nombra la clase
dominante de las siete y el razonamiento que converge en ella. "A las 9 va, a las 16 es inusable,
mañana va otra vez" es acumulación temporal, y ningún análisis de plan lo explicará.

> **Tú:** Muestrea la base de datos 30 segundos ahora, y otra vez después de comer.

→ **`fb_sample_activity`** lee los contadores MON$ dos veces a lo largo de la ventana e informa la
diferencia: registros leídos en secuencia y por índice, páginas movidas, versiones recogidas,
transacciones iniciadas, y si el horizonte de transacciones avanzó. Un horizonte que no se mueve
mientras las transacciones siguen empezando es recolección de basura que no llega a ninguna parte:
invisible en una sola instantánea, evidente entre dos.

Cada herramienta termina además declarando **qué no ha descartado**. Un plan limpio no es una
consulta rápida, y una ventana tranquila no es un sistema sano: MON$ cuenta el trabajo realizado,
nunca el tiempo esperando permiso para realizarlo.

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
