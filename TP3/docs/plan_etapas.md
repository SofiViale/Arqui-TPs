# Plan de seis etapas de desarrollo

Las etapas 1 y 2 están implementadas y verificadas en simulación RTL.
IF/ID/EX/MEM/WB son las cinco etapas del **hardware**, no la numeración de este plan.

| Etapa | Estado | Resultado / aceptación |
|---|---|---|
| 1. Diseño, ALU y bloques básicos | Completada en simulación RTL | Bloques, contratos, diagrama y pruebas automáticas; [evidencia](verificacion_etapa_1.md). |
| 2. Pipeline aritmético | Completada en simulación RTL | R/I/LUI superpuestas, traza por ciclo, reset/pausa y escritura condicionada por valid; [evidencia](verificacion_etapa_2.md). |
| 3. Memoria y dependencias | Pendiente | Loads/stores y programas lineales dependientes sin NOP manuales. |
| 4. Saltos y ejecución controlada | Pendiente | Branch/JAL/JALR, RUN/STEP/HALT/ERROR, descarte correcto y pipeline vacío. |
| 5. UART, carga y aplicación | Pendiente | Ensamblador → carga UART → ejecución → snapshot completo en PC. |
| 6. Integración y FPGA | Pendiente | Demostración en Basys 3 y métricas de implementación/temporización. |

## Etapa 1 — entregada

ALU original adaptada; decoder completo del subconjunto; inmediatos; banco con
debug y bypass; PC; registro genérico; IMEM/DMEM. Sin núcleo ejecutable.
Se cubren las ocho categorías de pruebas en cinco testbenches. No se requiere
demostración de FPGA para cerrar esta etapa; no se afirma haberla hecho.
Lecturas: impreso 303–310, 316–323, 346–348; PDF recortado indicado por el pedido
6–13, 19–26, 49–51. El PDF completo disponible usa 328–335, 341–348, 371–373.

## Etapa 2 — entregada: pipeline aritmético

Se integró `tp3_core` con las cuatro instancias y campos de
[arquitectura](arquitectura.md), fetch PC+4, selectores de operandos/ALU/LUI y
escritura WB con identidad y controles de la misma instrucción. MEM transporta
resultados aritméticos. Las escrituras exigen valid y core_enable; reset y pausa
se controlan externamente, sin RUN/STEP. `tp3_arithmetic_system` conecta IMEM y
la carga lógica desde testbench, provisoria hasta etapa 5. El
[README específico](../README_etapa_2.md) explica el funcionamiento por ciclos.

Aceptación cumplida: prueba de cada R/I/LUI, superposición real, traza PC/valid por
ciclo, destino correcto y ausencia de escrituras al pausar/invalidar. Se probó
bypass WB/ID con dos NOP entre productor y consumidor, sin implementar forwarding
ni detección de dependencias cercanas. 15.380 checks de integración y regresión
de etapa 1 aprobados. Lecturas: impreso 330–336, 345–350, 354–363;
PDF recortado 33–39, 48–53, 57–66.

## Etapa 3 — memoria y riesgos de datos

Agregar selección/extensión LB/LH/LW/LBU/LHU, alineación del dato SB/SH/SW y
validación de dirección original. Forwarding EX desde EX/MEM y MEM/WB, prioridad
al productor más nuevo. Una dirección de load no es el resultado cargado.
Detectar load-use mediante uses_rs1/uses_rs2, congelando PC e IF/ID, vaciando
ID/EX y permitiendo avanzar a las instrucciones mayores. Contemplar base y dato
de stores, x0, WB/ID y prioridad de pausa/reset/flush/stall.

Aceptar ALU→ALU, ambas fuentes, cadenas con mismo rd, productor x0, load→ALU,
ALU/load→store, base dependiente, falsos riesgos con bits de inmediato, máscaras
que preservan vecinos, extensión signed/unsigned y accesos inválidos.
Lecturas: impreso 309–311, 350–354, 363–375; PDF recortado 12–14, 53–57, 66–78.

## Etapa 4 — control de flujo y ejecución

Resolver saltos en EX con PC de la instrucción y operandos actualizados. JAL/JALR
producen PC+4; JALR borra bit 0 y verifica alineación. Descartar todas las jóvenes
incluida la entrada del siguiente registro. Añadir estados de ejecución, RUN y
STEP lógicos, HALT consumido una sola vez y drenaje por valid, además de watchdog
configurable para ausencia de HALT/bucles. Un error especulativo descartado no
debe abortar la ejecución.

Aceptar tomados/no tomados, adelante/atrás, bucles conocidos, dependencias
ALU/load→branch/JALR, stores y WB descartados sin efectos, HALT con mayores
pendientes y HALT especulativo. STEP avanza un ciclo incluso durante stall.
Comparar continuo/paso, pausa sin efectos y pipeline vacío en parada normal;
cancelación por watchdog se informa como error. Lecturas: impreso 339–343,
375–379; PDF recortado 42–46, 78–82; consigna 16–17.

## Etapa 5 — programación y observabilidad

Reutilizar RX/TX/baud/reset reales de TP2. Diseñar framing, longitud, comando,
payload, orden de bytes, respuesta, errores y timeout; justificar checksum.
Separar transporte, loader, controlador y serialización, con arbitraje de IMEM y
TX ocupado. Cargar solo con pipeline vacío, registrar entrada/longitud e impedir
residuos de programas anteriores. Fijar comandos LOAD/RUN/STEP/read/reset y la
política de limpieza/conservación indicada en [decisiones](decisiones.md).

Integrar ensamblador limitado al subconjunto, sin comprimidas ni reserva oculta
de x31, HALT exacto. La aplicación inicial puede ser CLI/TUI. Mostrar todos los
registros, campos de pipeline, memoria utilizada y causas de pausa/parada mediante
snapshot coherente con núcleo pausado. Las ubicaciones previstas son
`TP3/programs/` y `TP3/pc/`; aún no se crean.

Aceptar simulación UART completa con bytes consecutivos y busy, carga/ejecución
con resultados conocidos, snapshot verificable, reprogramación más corta sin
resíntesis, mensajes truncados/inválidos/timeout y secuencias RUN/STEP/reset/LOAD.
Lecturas: consigna 13, 15–17; libro impreso 359–363 / PDF recortado 62–66 para
interpretar controles. El libro no especifica el protocolo ni la Debug Unit.

## Etapa 6 — cierre en hardware

Completar top, XDC, sincronización y reset. Ejecutar programas combinados,
reprogramar por UART y comparar modos en placa. Medir setup, hold, caminos sin
restricciones, camino crítico, skew, recursos y frecuencia después de implementación.
No confundir simulación RTL con funcionamiento físico ni bitstream con timing
cerrado. Documentar limpieza, falta de HALT y frecuencia; cualquier cambio de
reloj usará recursos dedicados y ajustes de baud apropiados.

Aceptar evidencia reproducible en Basys 3 y reportes Vivado, conservando la
regresión de etapas previas. Lecturas: impreso 305–307, 329–335; PDF recortado
8–10, 32–38; consigna 18–19.
