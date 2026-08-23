# Ediciones y licencias

[← volver al README](../../README-ES.md)

En corto: **si lo usas sobre tus propias bases de datos, es gratis, y seguirá siéndolo.**
Sin prueba limitada, sin caducidad, sin clave de licencia, sin recuento de puestos, sin límite de
tablas ni de bases de datos. Instálalo, úsalo en producción, úsalo todos los días. No llama a casa.

Lo único que no puedes hacer es entregárselo a otro.

MCP Firebird es **source-available, no open source** en el sentido que le da la Open Source
Initiative. Decirlo claro importa más que una insignia: desde la **v0.2.0** se distribuye bajo la
[PolyForm Internal Use License 1.0.0](../../LICENSE). Las versiones hasta la **v0.1.0 incluida se
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
| Permisos registrados en la base de datos (`fb_audit_security`): PUBLIC, grant options, roles sin uso | ✅ | ✅ |
| Permisos de una cuenta de aplicación (`app_user_plan` + `fb_suggest_grants`): la entrevista y el SQL generado desde el catálogo | ✅ | ✅ |
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
