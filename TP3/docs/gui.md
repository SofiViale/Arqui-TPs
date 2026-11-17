# Guía de la interfaz gráfica del TP3

La aplicación controla la Debug Unit existente. No modifica RTL, pines, reloj ni protocolo. La CLI conserva su entrada `TP3/pc/tp3.py`; ambas interfaces importan `client.Client`, también accesible como `tp3.Client` para compatibilidad.

## Instalación y arranque en Windows

Python **3.10 o superior**, tkinter/ttk y Tcl/Tk 8.6; comunicación física con **pyserial 3.5**. Se verificó con Python 3.12.2, Tk 8.6 y pyserial 3.5. Tk se instala con la opción Tcl/Tk del instalador oficial de Python, no mediante pip. No hay servicios externos ni dependencias gráficas adicionales.

Abrir PowerShell en la raíz del repositorio:

```powershell
py -m pip install -r TP3/pc/requirements.txt
py TP3/pc/gui.py
```

Demostración sin placa (no necesita pyserial):

```powershell
py TP3/pc/gui.py --demo --program TP3/programs/demo.asm
```

`--program` sólo abre y valida un archivo local. No conecta, carga ni ejecuta automáticamente. En VS Code se puede ejecutar `TP3/pc/gui.py` con el intérprete de Python que tenga Tcl/Tk; para la demo, usar los argumentos anteriores. Si `py` no detecta una instalación pero `python --version` sí, usar `python` en esos mismos comandos o corregir la instalación del lanzador.

## Conexión y controles

Programar previamente la Basys 3 como indica el README. Conectar el micro-USB **PROG/UART**, encender y cerrar otras aplicaciones que tengan abierto el COM. **Actualizar puertos** enumera dispositivos y guarda sus descripciones en el log. Elegir el COM de la placa y **Conectar**. No elegir COM1 sólo porque aparezca: puede ser un puerto del equipo sin FPGA.

La configuración es fija y visible: **9600 baud, 8N1, sin control de flujo**, compatible con `system.v` y el bitstream actual. La PC no puede cambiar el divisor del hardware. La GUI distingue **puerto abierto, sin verificar** de **comunicación verificada**: exige una respuesta válida de STATUS con schema, capacidades y anchos correctos. No inicia una demo si esta verificación falla.

| Control | Operación y confirmación |
|---|---|
| Consultar STATUS | Consulta inocua. Flags, PC de búsqueda y ciclos se capturan juntos. No pausa. También permite recuperar comunicación después de un timeout. |
| Capturar (pausa CPU) | SNAPSHOT pausa antes de capturar 256 bytes y deja el núcleo pausado. Actualiza banco y pipeline. |
| Avanzar un ciclo | Un STEP; espera ACK y obtiene SNAPSHOT y, si hubo accesos, el rango usado de DMEM. No equivale a retirar una instrucción. |
| Ejecutar RUN | Habilita ciclos continuos hasta HALT/error/watchdog. No se pausa para actualizar durante RUN. |
| Pausar y capturar | PAUSE y SNAPSHOT. Conserva las instrucciones en vuelo. La recepción UART no detiene retrospectivamente el núcleo. |
| Reiniciar ejecución | RESTART descarta pipeline, reinicia PC a entry, banco, contador, causa y rango usado. Conserva IMEM. Limpia DMEM salvo opción explícita de conservar. Puede cancelar RUN. No vuelve válido un programa incompleto. |
| Cargar programa validado | STATUS, BEGIN, DATA consecutivos de hasta 128 bytes y COMMIT; después captura estado inicial. El progreso DATA refleja bytes con ACK; sólo COMMIT confirma la carga completa. No ejecuta automáticamente. |
| Pausar y leer DMEM | MEMORY por bloques de hasta 128 bytes. Deja pausado. Dirección y cantidad en bytes, múltiplos de 4, rango 0..1023 inclusive. |
| Aplicar límite | LIMIT detenido, uint32; cero deshabilita watchdog. El límite cuenta ciclos habilitados, incluidos stall y drenaje, no tiempo UART. |
| Desconectar / cerrar ventana | Cierra el puerto sin enviar PAUSE. La CPU puede seguir ejecutando. Cerrar durante una operación cancela la espera; la operación podría haberse ejecutado. |

Durante una operación se deshabilitan comandos y carga. Sólo el hilo UART abre, lee, escribe y cierra el puerto; no se mezclan solicitudes, respuestas ni polling. Tk procesa eventos desde una cola en su hilo principal. La exportación y la ventana siguen disponibles durante transferencias.

La carga requiere evidencia de CPU detenida y pipeline vacío: después de conectar, **Capturar** para habilitarla. Si hay instrucciones pendientes, **Reiniciar ejecución** y luego cargar. No se vacía silenciosamente el pipeline. RUN/STEP requieren programa válido y estado no terminal. Un estado terminal exige RESTART o nueva carga.

El estado **drenando** tiene código 2 tanto si avanza automáticamente como si está detenido. STATUS no transmite `running` para distinguirlos. Hasta una captura/pausa explícita, la GUI mantiene STEP y carga deshabilitados ante esa ambigüedad. SNAPSHOT sí contiene `running`.

La casilla **STATUS cada 1,5 s; capturar al finalizar RUN**, activa por defecto, consulta sólo STATUS durante RUN/drenaje, una vez terminada la operación anterior. Tras observar estado 3 o 4, captura registros/pipeline y lee el rango utilizado, alineado hacia afuera. Si se desmarca, usar Consultar STATUS para detectar el fin de un RUN iniciado desde la GUI o Capturar para pausar explícitamente. No hay avance automático mediante STEP.

**HALT** es EBREAK exacto `00100073`: se reconoce en EX, descarta jóvenes y drena mayores. El estado finalizado se alcanza cuando el pipeline ya está vacío. Una pausa mantiene los valid; no representa HALT. Las causas ilegales, fetch, DMEM, salto o watchdog se muestran como error, incluso si ya hay resultados parciales comprometidos. El reset físico btnC invalida el programa y exige volver a cargar; no es un comando UART ni se confunde con RESTART.

## Vistas y procedencia

**Programa y carga.** Se reutiliza `assembler.assemble`, sin otro ensamblador. Acepta fuente ASM (también en un archivo de texto), etiquetas y comentarios del formato existente. La salida hexadecimal de `tp3.py assemble` es una lista de palabras para inspección, no un formato de entrada de carga. Se rechazan sintaxis inválida, vacío, más de 256 palabras, entrada desalineada o fuera del programa antes de BEGIN. El programa siempre se escribe desde IMEM[0]; entry es el inicio de ejecución, no la dirección de carga. Cada palabra se envía little-endian. Se muestran dirección byte, palabra y desensamblado estricto del subconjunto; desconocidas permanecen en hexadecimal. Cambiar el archivo en disco después de abrirlo no cambia las palabras ya previsualizadas; abrirlo nuevamente para recargar su contenido.

La tabla dice **LOCAL**. El ACK de DATA/COMMIT confirma aceptación del loader y no una comparación con IMEM. **El protocolo no permite leer IMEM.** La confirmación conserva sus propias palabras, entry y fecha en el JSON, independientemente del archivo que después se seleccione. El azul sólo indica coincidencia con el último **PC de fetch** observado, nunca retiro ni una lectura de instrucción desde FPGA.

**Registros.** x0..x31 recibidos, con columnas hexadecimal, unsigned y signed simultáneas. Amarillo indica cambio respecto de la captura anterior de la misma sesión. x0 distinto de cero se muestra sin modificar, se pinta rojo y se registra la anomalía. Al reconectar se borra la comparación con la sesión anterior.

**Pipeline.** Cinco paneles IF/ID/EX/MEM/WB, con colores y scroll. IF muestra únicamente el PC de búsqueda: la instrucción y valid de fetch no se transmiten. ID, EX, MEM y WB muestran los registros **IF/ID, ID/EX, EX/MEM y MEM/WB** respectivamente: PC, instrucción y todos los campos disponibles, incluidos operandos, inmediato, registros, resultado, dato de store/WB y controles. Son el estado a la entrada de cada etapa. Valid=0 significa payload inválido/burbuja; los bits pueden conservar información sin efectos. Una NOP válida tiene valid=1 y palabra `00000013`. Los errores fetch FI/IX e illegal IX se muestran aparte.

Los selectores de forwarding, stall y flush **no se exportan por UART**, aunque existan internamente en `processor.v`. Se indican como **No disponible**. Los operandos IX fueron capturados en ID y no son necesariamente los operandos posteriores al forwarding. No se animan ciclos no observados ni se deducen eventos a partir del color.

**DMEM.** Tabla de dirección byte, bytes little-endian, palabra hex, unsigned y signed. Es lectura explícita por rango; no hay escritura soportada ni polling de toda la memoria. El snapshot informa el intervalo exacto de bytes accedidos con éxito (incluye loads y stores); la lectura de palabras puede incluir huecos de ese intervalo. Los extremos son inclusivos.

**Registro y exportación.** El log conserva solicitudes, ACK, cargas, capturas, errores y exportaciones. El JSON `TP3-GUI-1` incluye fecha UTC ISO 8601, origen real/simulado, sesión, configuración de conexión, operación pendiente, STATUS original, bytes y campos de SNAPSHOT, DMEM, programa local, ACK de carga y log. Cada lectura conserva su fecha y marca de antigüedad. El log también identifica origen/sesión por entrada.

Un SNAPSHOT es coherente internamente porque el RTL pausa e inhibe el botón local durante su captura/respuesta. STATUS, SNAPSHOT y MEMORY son **observaciones separadas**, incluso si tienen fechas próximas. La memoria leída en varios comandos tampoco es atómica: el botón local puede actuar entre órdenes. Tras RUN, STEP, reinicio, errores o desconexión, las lecturas previas se marcan **ANTERIOR**. Reconectar limpia las vistas observadas; no presenta datos antiguos como actuales. La edad no garantiza ausencia de intervenciones del botón de la placa después de una lectura.

## Recuperación de errores

| Mensaje / situación | Acción |
|---|---|
| No hay COM de placa | Revisar alimentación, cable USB de datos, PROG/UART y controlador. Actualizar puertos. |
| Puerto ocupado/sin permisos | Cerrar otra GUI, CLI, terminal serial o monitor de Vivado que lo use; volver a conectar. |
| Puerto abierto, sin verificar | STATUS no produjo respuesta compatible. Verificar bitstream, COM y 9600 baud; Consultar STATUS o desconectar. |
| Timeout / CRC / trama incompleta | La respuesta puede haberse perdido después de ejecutar la orden. No repetir STEP ni escrituras automáticamente. Consultar STATUS; capturar explícitamente antes de continuar. |
| USB desconectado | Se cierra el transporte y las lecturas quedan históricas. Reconectar físicamente y abrir una sesión nueva. |
| Schema/anchos/capacidades incompatibles | Usar aplicación y bitstream del mismo TP3. No se permite cargar con capacidades desconocidas. |
| BEGIN ocupado / carga deshabilitada | Capturar para verificar valid. Si el pipeline no está vacío, reiniciar ejecución antes de cargar. |
| DATA/COMMIT interrumpido | No hay rollback. BEGIN pudo invalidar el programa anterior; consultar STATUS. Reabrir/validar y comenzar una carga nueva desde BEGIN cuando esté detenido/vacío. |
| Error de programa | Revisar causa y PC de parada/error. HALT, error y watchdog no se confunden con pausa. |
| `No installed Python found` | Revisar el Python Launcher; probar `python --version` y el mismo comando con `python`. |
| `Can't find a usable init.tcl` / falta tkinter | Reparar Python incluyendo Tcl/Tk; ejecutar en la sesión normal de Windows. Algunos entornos aislados no permiten acceder a esa instalación. |

El timeout incluye solicitud y respuesta máxima, peor escape, baud y margen de dispositivo: `2 + 2*(bytes_solicitud + 2*519 + 2)*10/9600` segundos, además de la escritura limitada y lecturas seriales de hasta 100 ms. Los errores deshabilitan órdenes con efectos hasta recuperar STATUS. No hay reintentos automáticos ni cambio silencioso a demostración.

Si el comando ya recibió ACK y falla únicamente la lectura posterior, el log conserva esa confirmación. En particular, no se presenta como carga fallida un COMMIT confirmado seguido de un timeout de SNAPSHOT. Se recuperan las vistas con STATUS/captura sin repetir el comando con efectos.

## Prueba manual reproducible

Usar `TP3/programs/demo.asm`, entrada 0 y **Conservar DMEM desmarcado**. No pulsar los botones locales durante la secuencia. Se puede ensayar con `--demo`; eso no valida la placa.

1. **Conectar y capturar.** Con placa recién reseteada se espera pausado, programa inválido y pipeline vacío. Con una placa previamente usada, el estado inicial puede ser distinto: observarlo y reiniciar ejecución si hace falta. La conexión sólo se declara verificada tras STATUS.
2. **Abrir demo.asm y cargar.** Tabla LOCAL de seis palabras / 24 bytes. Esperar COMMIT confirmado y captura inicial: PC=0, ciclos=0, banco cero, valid=0, programa válido, memoria usada sin accesos. La limpieza DMEM termina antes del ACK de BEGIN. No se afirma lectura de IMEM.
3. **Consultar estado inicial.** STATUS no avanza ni pausa adicionalmente; deben permanecer PC=0 y ciclos=0. Capturar permite revisar los cuatro valid sin cambios.
4. **Avanzar por ciclos.** En el primer STEP: PC=4, FI válido con `00700093`, x1 aún cero. Se necesitan etapas hasta WB. En el quinto ciclo x1=7; x2=12 llega en el sexto. La dependencia `lw x3` → `add x4` produce una burbuja load-use: entre ciclos 5 y 6 PC sigue en 20 y valid IX pasa a cero; la GUI no afirma recibir una señal stall. La instrucción de load aún debe llegar a WB. El store de x2 escribe bytes `0c 00 00 00` y registra rango usado 0..3. No hay saltos en este programa, pero HALT descarta las instrucciones jóvenes al resolverse en EX. Se obtiene captura después de cada STEP; DMEM usada se lee por separado si ya hubo accesos.
5. **Ejecutar RUN.** Por ejemplo, tras dos STEP, presionar RUN y esperar el polling de STATUS. Debe terminar **finalizado, causa HALT**, pipeline vacío. Para esta secuencia sin botones locales: 11 ciclos habilitados, PC fetch=28 y fault_pc=20 (PC del HALT). RUN termina mucho antes de que una lectura UART humana pueda observar sus ciclos intermedios; la demo lo ralentiza deliberadamente.
6. **Revisar registros y memoria.** Captura final automática con polling activo: x0=0, x1=7, x2=x3=12, x4=19 (`00000013`), x31=0 y los demás cero. DMEM usada=0..3, lectura final `0c 00 00 00`, palabra 12. En DMEM, dirección `0`, cantidad `4`, Pausar y leer permite repetir la observación; su fecha será independiente de la captura final.
7. **Exportar evidencia.** En Registro y exportación, guardar JSON. Comprobar `source`, `session_started_at`, contexto de conexión, `snapshot.decoded.registers[4]=19`, valid=0 en cabecera y `memory.raw_hex="0c000000"`. Si se eligieron 16 bytes en DMEM, el raw contiene además los siguientes 12 bytes cero. Conservar el archivo real de placa separado de las demos.

Para repetir: RESTART limpia por defecto banco/pipeline/DMEM, conserva IMEM y deja pausado. Se puede reprogramar `loop.asm`, `bytes.asm` o `error.asm` sin resintetizar. En `error.asm`, la finalización esperada es error DMEM desalineada, no HALT.

## Implementación y límites

`protocol.py` conserva framing y CRC; `client.py` comparte solicitudes, longitudes, capacidades, carga y lecturas entre CLI y GUI. `model.py` valida, desensambla y registra procedencia. `worker.py` tiene el único dueño del puerto y una cola acotada; `gui.py` contiene sólo presentación/interacción. `demo.py` implementa un transporte con las mismas tramas y un modelo educativo de ciclos, riesgos, saltos, drenaje y errores. RUN simulado avanza a 40 ciclos/s al atender consultas; no representa 100 MHz ni latencias UART/USB reales. Sus resultados se contrastan con los 50 programas dirigidos existentes, no se utiliza como verificación del RTL.

No se implementan lectura de IMEM, escritura DMEM, señales internas ausentes ni reset físico por UART. Las pruebas de conexión USB, pérdida física del cable, programación de Basys 3 y equivalencia de datos reales quedan pendientes hasta disponer de placa. La [verificación](verificacion_gui.md) detalla qué se ejecutó.
