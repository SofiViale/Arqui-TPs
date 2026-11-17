# Verificación final del TP3

Fecha de cierre local: **3 de noviembre de 2026**. Se implementaron las etapas 3–6 a nivel de fuentes, herramientas de PC, integración, restricciones y flujo FPGA. La prueba física en Basys 3 sigue pendiente; no se declara realizada.

**Ampliación del 16/11/2026:** se incorporó una GUI, cliente compartido con la CLI y demostración explícita. La [verificación de la GUI](verificacion_gui.md) registra 32 pruebas Python y diez bancos RTL PASS, navegación visual y límites. No modifica RTL ni sustituye la prueba física pendiente. Este informe del 3/11 conserva su fecha y métricas originales.

## Estado y entorno

Windows, Python 3.13.15 y Vivado/xsim 2026.1, build 6511674. Icarus no estaba en PATH ni existía la copia local citada por las evidencias históricas. La batería acumulada se ejecutó con xvlog/xelab/xsim. El RTL se compila como Verilog; los bancos se compilan como SystemVerilog para habilitar las assertions `$fatal` en xsim.

TP1 y TP2 permanecen sin modificaciones (`git diff -- TP1 TP2` vacío). El diseño final instancia una única ALU, desde TP1, y reutiliza RX/TX/baud/reset de TP2. Las FSM de calculadora y la ALU duplicada de TP2 están excluidas. Los núcleos aritméticos de etapa 2 se conservan sólo para regresión.

| Nivel | Resultado |
|---|---|
| Implementado | Pipeline completo, memorias, riesgos, saltos, HALT/errores/watchdog, UART/loader/debug, ensamblador/CLI y top Basys 3 |
| Verificado en simulación | Diez bancos RTL PASS, 11 pruebas Python PASS |
| Sintetizado | Sí, xc7a35tcpg236-1 |
| Implementado y timing revisado | Sí, 100 MHz, setup/hold/pulse width sin violaciones |
| Bitstream | Generado en `TP3/build/vivado/tp3.bit` |
| Probado físicamente | No; no se enumeraron puertos seriales de placa, no se ejecutó programación JTAG ni UART física |

## Regresión ejecutada

```powershell
py TP3/scripts/regress.py
py -m unittest discover -s TP3/scripts -p test_host.py -v
py TP3/pc/tp3.py --help
py TP3/pc/tp3.py assemble TP3/programs/demo.asm
```

Todos estos comandos finalizaron con código 0. La CLI y las pruebas usan los módulos de ensamblado, framing y snapshot entregados. pyserial está disponible en este entorno; en otra PC se instala con el requirements documentado.

| Banco | Resultado | Evidencia |
|---|---|---|
| alu_tb | PASS | 66 comprobaciones |
| decode_tb | PASS | 5.280 comprobaciones |
| register_file_tb | PASS | 229 comprobaciones |
| state_tb | PASS | 42 comprobaciones |
| memory_tb | PASS | 1.020 comprobaciones |
| pipeline_tb histórico | PASS | 15.380 comprobaciones, 288 flancos, 63 commits, 207 observaciones con superposición |
| processor_tb completo | PASS | 30.416 comprobaciones; 50 programas en RUN y STEP, banco completo y toda DMEM; pausa simultánea con RUN/STEP y escrituras pendientes; reset y watchdog |
| uart_system_tb | PASS | 69 respuestas, 3.582 bytes seriales recibidos y verificados por Python |
| uart_baud_tb | PASS | UART a 9600 baud, break/error de stop, recuperación y respuesta STATUS completa con CRC |
| board_tb | PASS | Rebotes, pulsación sostenida, segunda pulsación, reset y salidas locales |

Los seis bancos históricos más el nuevo banco de procesador suman **52.433 comprobaciones**. Los intercambios UART y los once tests Python se informan aparte, no se suman como si fueran assertions equivalentes.

La batería Python comprueba encodings literales conocidos, etiquetas adelante/atrás, límites de inmediatos, x31, errores con línea, CRC conocido, todos los bytes escapables, corrupción/resincronización y los anchos/campos/padding de snapshot. Los esperados de programas son constantes independientes del RTL; el ensamblador se utiliza sólo para construir estímulos.

La integración UART transmite bits por RX del diseño y decodifica bits de TX con un receptor de testbench independiente. Comprueba demo x4=19 y DMEM[0]=12, estados finales, pipeline ocupado en STEP, rechazo de BEGIN ocupado, memoria, reprogramación más corta, programas sin HALT, watchdog, entrada distinta de cero, CRC/versiones/longitudes inválidos, payload máximo, mensajes truncados y recuperación. Una carga DATA interrumpida después de BEGIN permanece inválida. Se comprueban ambas políticas de DMEM (limpiar/conservar) y escapes en solicitudes y respuestas. La prueba acelerada conserva los módulos UART reales; la prueba adicional usa el divisor de producción a 9600 baud.

La última optimización temporal conserva estos resultados: el payload ID/EX se captura independientemente del flush, mientras `valid` controla sus efectos; el rango de DMEM se valida contra umbrales constantes equivalentes a dirección+tamaño, sin recortar la dirección. No se alteró el número de etapas ni la latencia de RAM.

## Síntesis, implementación y bitstream

Se ejecutó el flujo `build.tcl`; la última implementación quedó interrumpida durante placement al finalizar la sesión anterior. Se retomó mediante:

```powershell
vivado -mode batch -source TP3/scripts/resume.tcl -log TP3/build/vivado_resume.log -journal TP3/build/vivado_resume.jou
```

`resume.tcl` verifica que ningún fuente ni restricción sea posterior al checkpoint y que Vivado no considere obsoleta la síntesis. Reinicia únicamente implementación y usa el mismo `reports.tcl` que el flujo completo. Finalizó con código 0 y `Bitgen Completed Successfully`. Para reconstruir desde cero, usar el comando `build.tcl` del README.

| Métrica final post-route | Valor |
|---|---:|
| Reloj / período | 100 MHz / 10,000 ns |
| Setup WNS / TNS | +0,235 ns / 0,000 ns |
| Hold WHS / THS | +0,068 ns / 0,000 ns |
| Pulse-width worst slack | +3,750 ns |
| Endpoints con violación setup / hold | 0 / 0 |
| Endpoints internos sin restricción | 0 |
| Registros sin reloj / loops combinacionales | 0 / 0 |
| DRC | 0 checks con problemas |
| CDC entradas asíncronas | 10 seguras, 0 inseguras, 0 desconocidas |
| LUT | 9.779 / 20.800 (47,01 %) |
| Flip-flops | 5.534 / 41.600 (13,30 %) |
| LUT de RAM distribuida | 528 |
| Latches | 0 |

El camino crítico final va desde `system/packet/pos_reg[6]` al clock-enable de `escaped_byte_reg[7]`: retardo de datos **9,485 ns**, compuesto por lógica 2,661 ns y ruteo 6,824 ns, con 12 niveles lógicos. El **skew es −0,040 ns**, una magnitud distinta del retardo combinacional. No se usa el período del testbench como evidencia física ni se afirma una frecuencia máxima medida.

`check_timing` muestra diez entradas y 25 salidas activas sin delays externos pero con excepciones explícitas: entradas asíncronas sólo hasta el primer sincronizador y salidas de display/LED/UART sin reloj síncrono externo. No hay endpoints internos sin restricciones. `report_cdc` identifica los diez sincronizadores como seguros. Las salidas constantes no necesitan camino temporal. No se introdujeron excepciones entre etapas del núcleo ni se cambió el reloj para alcanzar el cierre.

El primer intento completo a 100 MHz tenía WNS −0,782 ns, WHS +0,043 ns y 507 endpoints de setup fallidos. El script rechazó generar bitstream. Se redujeron los buffers y el fanout de flush, y se simplificó la comparación de rango; el resultado final de arriba sustituye aquel intento. Los reportes anteriores permanecen en `build/timing_before_optimization/`; sus valores no se presentan como un cierre exitoso.

También se corrigieron bucles Tcl que el lector XDC no aceptaba, reemplazándolos por restricciones explícitas por pin. Un intento anterior de xsim se cerró con access violation después de PASS; se lo trató como fallo de herramienta. La regresión final completa terminó normalmente con código 0.

## Evidencia conservada

[Manifest y hashes](evidence/2026-11-03/manifest.json), [resultados RTL](evidence/2026-11-03/regression.json), [timing](evidence/2026-11-03/timing.rpt), [utilización](evidence/2026-11-03/utilization.rpt), [DRC](evidence/2026-11-03/drc.rpt), [CDC](evidence/2026-11-03/cdc.rpt), [restricciones temporales](evidence/2026-11-03/check_timing.rpt). En ese directorio también están los diez logs de simulación y los caminos críticos de setup/hold. Son copias de archivos generados por las herramientas, no salidas reconstruidas.

SHA-256 del bitstream generado:

```text
3fa073fcc90ee7aaa4f517c88482640927814d388e86cf5ee925d66877390e21
```

Los informes históricos de etapas 1 y 2 se conservaron. Los nuevos resultados de sus bancos provienen de la regresión actual, no de reutilizar los resultados de octubre.

## Validación física restante

Conectar y programar una Basys 3; ejecutar la primera prueba del README y guardar la salida real de `status`, `run --wait`, `snapshot --used-memory` y `memory 0 4`. Confirmar x1=7, x2=x3=12, x4=19, pipeline vacío y bytes `0c 00 00 00`. Verificar display `0013` con sw[4:0]=4, sw5=0, sw6=0.

Repetir con loop, bytes y error controlado; comprobar RUN contra STEP, botón sostenido, ambas mitades del display, reset físico y carga de un programa más corto sin resintetizar. La generación del bitstream, el análisis estático y la simulación no sustituyen estos pasos. El margen de setup positivo de 0,235 ns corresponde a esta implementación; cualquier cambio de RTL, opciones o herramientas requiere regenerar y revisar los reportes.
