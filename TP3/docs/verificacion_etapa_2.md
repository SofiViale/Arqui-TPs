# Verificación de la etapa 2 — pipeline aritmético

**Fecha: 23/10/2026. Estado: completada en simulación RTL.** Se ejecutaron las
pruebas del núcleo integrado y la regresión de los cinco bancos de etapa 1.
No quedan pruebas esenciales de esta etapa pendientes. La prueba en placa y
el cierre de temporización siguen reservados para etapa 6.

## Entorno y comandos ejecutados

Windows/PowerShell, Python 3.12 e Icarus Verilog 12.0 (devel), revisión
`s20150603-1539-g2693dd32b`, reutilizando la copia local que se había extraído en
`TP3/build/tools/icarus/app/bin`. No se instalaron herramientas nuevas.
La terminal aislada falló al inicializar (`setup refresh had errors`); se obtuvo
autorización para ejecutar los comandos fuera de ese entorno.

Desde la raíz:

```powershell
python TP3/scripts/simulate.py --stage 2
python TP3/scripts/simulate.py
```

Los dos procesos devolvieron **0**. El runner utiliza Verilog-2005, tops/includes
explícitos y la ALU original de TP1. Se conserva el aviso informativo de
sensibilidad de `always @*` a todas las palabras de IMEM/DMEM, propio de sus
lecturas combinacionales. No hubo errores de compilación ni assertions fallidas.

## Resultados

| Testbench | Resultado | Comprobaciones |
|---|---|---:|
| alu_tb | PASS | 66 |
| decode_tb | PASS | 5.280 |
| register_file_tb | PASS | 229 |
| state_tb | PASS | 42 |
| memory_tb | PASS | 1.020 |
| pipeline_tb (nuevo) | PASS | 15.380 |
| **Total** | **PASS** | **22.017** |

Salida del banco integrado:

```text
PASS: pipeline_tb (15380 checks, 288 edges, 63 commits, 207 overlap cycles)
```

`edges` cuenta los flancos explícitamente ejercitados por la tarea `cycle`,
incluidos reset y pausa. No cuenta los flancos de programación de IMEM.
`commits` cuenta escrituras arquitectónicas efectivas, excluyendo x0 y NOP;
se acumula sobre todas las secuencias y reinicios de la prueba.
`overlap cycles` cuenta observaciones posteriores al flanco con los cuatro valid
en uno, incluidas observaciones durante pausa. No es una medición de IPC.
La traza demuestra además avance simultáneo en flancos habilitados.

## Criterios de aceptación cubiertos

| Criterio | Prueba y evidencia |
|---|---|
| Todas las R requeridas | ADD/SUB/SLL/SRL/SRA/AND/OR/XOR/SLT/SLTU con resultados literales, incluyendo operandos negativos y comparación signed/unsigned. |
| Todas las I aritméticas y LUI | ADDI/ANDI/ORI/XORI/SLTI/SLTIU/SLLI/SRLI/SRAI/LUI, extensión de signo, shifts de 31 y resultado superior LUI. |
| Cinco etapas reales | Cada instrucción conserva PC e instruction por IF/ID, ID/EX, EX/MEM y MEM/WB. Se compara validez contra una cola independiente en cada ciclo. MEM transporta la aritmética. |
| Destino y dato correctos | Cada escritura WB compara rd, dato, PC e instrucción contra la entrada esperada del programa. Se examinan además los 32 registros después de cada flanco de prueba. |
| Superposición | El programa aritmético llena los cuatro registros y completa escrituras en flancos consecutivos. Los primeros ciclos están ejemplificados en el README. |
| x0 y x31 | Intento de escribir x0 descartado; x31 escrito y utilizado como fuente, sin reservarlo. Se verifican conteos exactos de escrituras del programa principal. |
| Pausa global | Se repite el mismo programa con pausas en distintos puntos. Se comparan todos los bits de PC/pipeline y el banco completo. No hay pérdida ni duplicación de escrituras. |
| Reset | Reset con pipeline lleno y WB pendiente, enable activo e inactivo. Limpia PC, cuatro payloads/valid y banco; suprime la escritura pendiente y conserva IMEM. |
| WB/ID | Productor, dos NOP, consumidor. También se pausa con WB e ID coincidentes; al reanudar, el bypass entrega el dato que corresponde. |
| Burbujas | Retirar fetch manteniendo core_enable permite completar las instrucciones y vaciar los cuatro registros en cuatro ciclos. Un payload inválido no genera escritura. |
| Alcance limitado | LW/SW/BEQ/BNE/JAL/JALR/HALT son reconocidos pero reportados como no ejecutables; ECALL/MUL/palabra cero se reportan ilegales. No escriben, no redirigen PC ni detienen automáticamente. |
| Carga provisional | Se carga IMEM por su puerto lógico con núcleo detenido y vacío. Se comprueba rechazo de carga durante ejecución, pausa con pipeline ocupado y reset. |
| Rango de fetch | Se ejecuta la última palabra de una IMEM de 128 palabras. Las búsquedas siguientes reportan error, mantienen PC en 512 e introducen burbujas sin alias. La última instrucción válida completa su escritura. |

## Independencia y repetibilidad

Los programas se construyen en el testbench con funciones que codifican campos
R/I/U y constantes de resultado explícitas. No se usa el decoder, la ALU o el
banco del diseño para generar resultados esperados. La cola de índices de
programa modela únicamente el tránsito de instrucciones y su clasificación
esperada; el scoreboard registra sus escrituras conocidas.

Los estímulos se aplican en negedge. La comparación ocurre después de posedge
más 1 ns; los barridos de debug usan intervalos de 10 ps y terminan antes del
siguiente flanco. Esto evita carreras con las asignaciones no bloqueantes.
Se inicializan explícitamente las 128 palabras de IMEM en cada carga; nunca
se asume que RAM sin escribir contiene cero.

`check.vh` usa `$fatal(1)` ante una condición falsa o desconocida y tiene un
watchdog de simulación. El script limita cada proceso a 60 segundos y exige
retorno cero y un marcador PASS del top correcto. Solo compila las fuentes
necesarias; no incorpora la definición duplicada de ALU existente en TP2.

## Artefactos generados

| Ruta relativa a TP3 | Contenido |
|---|---|
| `build/pipeline_tb_compile.log` | Compilación y avisos del nuevo banco |
| `build/pipeline_tb.log` | Resultado y contadores de simulación |
| `build/pipeline_trace.csv` | Estado anterior a cada flanco de prueba: PC/valid/instrucción por etapa y escritura WB |
| `build/results_stage_2.json` | Resultado al seleccionar etapa 2 |
| `build/results.json` | Resultado de la regresión completa |

Todos se regeneran con los comandos anteriores y están ignorados por Git.
La ruta de la traza se pasa explícitamente por `+TRACE=…`; el runner resuelve
fuentes, includes y salidas respecto de su archivo, independientemente del cwd.
Las ejecuciones con `--stage` o `--bench` escriben resúmenes separados para no
reemplazar el último resultado de la regresión completa.

## Límites de esta evidencia

Las pruebas demuestran secuencias **aritméticas con dependencias separadas**.
No hay resolución general de riesgos, forwarding ni stalls; un consumidor
demasiado próximo puede leer un dato anterior sin diagnóstico.
El drenaje depende de retirar fetch desde el testbench. No demuestra HALT,
control RUN/STEP, watchdog hardware ni gestión de longitud/reprogramación UART.
La memoria de datos no participa en esta integración.

No se ejecutaron Vivado, síntesis, análisis formal, implementación, mediciones
de frecuencia/recursos ni FPGA/UART física. El reloj de 10 ns del testbench es
un estímulo de simulación y no demuestra funcionamiento físico a 100 MHz.
TP1 y TP2 permanecen sin modificaciones. El informe de etapa 1 se conserva
como evidencia histórica; las etapas 3–6 siguen pendientes.
