# Registro de decisiones — etapa 1

Fecha de inspección e implementación: 7 de octubre de 2026.

## Fuentes y alcance de la inspección

Se leyó el texto completo de las 20 páginas de `D:/Descargas/TRABAJO FINAL 2026.pdf`.
La página 14 confirma las 32 instrucciones requeridas; 13 y 15–19 confirman
reprogramación por UART, observabilidad, modos de ejecución y análisis de reloj.
También existe una copia con sufijo `(1)`; no fue necesaria para el diseño.

No se encontró el archivo exacto `Capitulo libro Procesador.pdf` en el repositorio,
Descargas ni la búsqueda en Documentos. Sí se encontró
`D:/Descargas/Computer_Organization_and_Design_4th-español.pdf` (914 páginas).
Se consultaron las páginas impresas 303–310, 316–323 y 346–348, equivalentes a
328–335, 341–348 y 371–373 de ese PDF completo. Los números del PDF recortado
que figuran en el pedido se conservan como guía, sin afirmar haber leído ese archivo.

Se inspeccionó `D:/Descargas/risc-v-risky-edition-main.zip`: `docs/core_specs.md`,
la organización `riscv_programs/` y `src/backend/`, y el ZIP interno
`archived_vivado_proj/prj_riscv_fpga_top.xpr.zip`. Dentro se localizaron 27 fuentes
`.sv` bajo `prj_riscv_fpga_top/prj_riscv_fpga_top.srcs/sources_1/imports/src/` y
se leyeron `register_file.sv`, `data_memory.sv` y `pipeline_register.sv`.
La referencia aporta organización, debug y máscaras; no se importó su código.
Su aprobación es información aportada por el usuario, no una validación propia.

Se contrastaron inmediatos, shifts y saltos con la
[especificación oficial RV32I, versión 2.1](https://docs.riscv.org/reference/isa/v20260120/unpriv/rv32.html).
La diapositiva 10 de la consigna describe incorrectamente rd como origen del
destino de JAL: el destino es PC+inmediato y rd recibe PC+4. JALR usa rs1 y limpia
el bit cero. No se trasladan las codificaciones, PC+4 como base de branch ni el
desplazamiento extra de dos bits del ejemplo MIPS.

No se encontraron `AGENTS.md` aplicables en el repositorio o sus ancestros
inspeccionados. El estado inicial de Git estaba limpio y TP3 vacío. Git requirió
`-c safe.directory=…` en cada consulta por diferencia de propietario del entorno;
no se modificó la configuración global ni se hicieron commits.

## Inventario real y reutilización

Las rutas siguientes son relativas a la raíz del repositorio. Todos los módulos
UART usan reset activo alto y reloj por flanco positivo.

| Módulo / archivo | Interfaz y parámetros existentes | Uso / adaptación |
|---|---|---|
| `alu`, `TP1/src/alu.v` | N_DATA=8, N_OP=6; a,b:N_DATA; op:N_OP; res:N_DATA; zero/overflow/carry_out | Instancia original N_DATA=32/N_OP=6 en TP3; sin modificar TP1. |
| `TP1/src/alu_testbench.v` | Pruebas dirigidas para 8 bits; registra fallos en `fails` | Inspeccionado. TP3 incorpora comprobaciones propias con salida no cero. |
| `TP1/src/basys3_top.v`, `TP1/constrains/basys3.xdc` | Top de placa; reloj y restricciones Basys 3 | Sin cambios; TP3 no importa este top ni sus pines. |
| `uart_rx`, `TP2/src/uart_rx.v` | DATA_BITS=8; clk/reset/tick_16x/serial_rx; rx_data:DATA_BITS, rx_valid_pulse, frame_error | Reutilización en etapa 5. Ya incluye sincronización de RX de dos FF. |
| `uart_tx`, `TP2/src/uart_tx.v` | DATA_BITS=8; clk/reset/tick_16x/tx_start_pulse, tx_data; serial_tx, tx_busy, tx_done_pulse | Reutilización etapa 5. Respetar busy y pulso de aceptación. |
| `baud_rate_generator`, `TP2/src/baud_rate_generator.v` | CLK_FREQ=100000000, BAUD_RATE=9600; clk/reset → tick_16x | Conservar inicialmente. Tick es habilitación, nunca reloj del núcleo. |
| `reset_sync`, `TP2/src/reset_sync.v` | clk/reset → reset_out; dos flancos de liberación | Reutilizable en el límite de placa, integración pendiente. |
| `rx_interface_fsm`, `TP2/src/rx_interface_fsm.v` | rx_data:8, rx_valid_pulse, frame_error, operation_ready → a/b:8, op:6, operation_valid_pulse, protocol_error | Protocolo de calculadora; no es loader del procesador. Se reemplazará su función en TP3 etapa 5. |
| `tx_interface_fsm`, `TP2/src/tx_interface_fsm.v` | DATA_BITS=8; operation_valid_pulse, alu_result, tx_busy/done → tx_data/start, operation_ready | Interfaz de calculadora, no serializa snapshots de TP3. |
| `tp2_top`, `TP2/src/tp2_top.v` | CLK_FREQ=100 MHz, BAUD_RATE=9600; clk/reset/RX → TX/errores | Confirma configuración; no se instancia en TP3. |
| `alu`, `TP2/src/alu.v` | Otra definición del nombre `alu`, con interfaz coincidente | Se excluye explícitamente para evitar colisión. TP3 compila solamente la ALU de TP1. |
| `TP2/sim/*_tb.v`, `TP2/scripts/simulate.py` | Bancos baud, TX, RX, interfaces y top; assertions/timeouts | Inspeccionados como guía de pruebas. No se alteran ni se declara nueva validación de TP2. |
| `TP2/pc/` | Calculadora Python, protocolo y cliente serial | Aplicación existente; aún no controla TP3. |
| `TP2/constrains/basys3.xdc` | create_clock de 10 ns | Confirma objetivo inicial de 100 MHz. No es evidencia de cierre temporal de TP3. |

TP1 contiene siete operaciones directamente aprovechables: ADD, SUB, AND, OR,
XOR, SRL y SRA. El adaptador traduce el código interno y, solo en SRL/SRA, limita
el operando B a cinco bits. SRA de TP1 ya usa `$signed(a)`, por lo que no necesita
reimplementación. SLL, SLT y SLTU se agregan en TP3; SLT usa comparación signed.
NOR no pertenece al subconjunto pedido. Se ignoran overflow/carry de TP1 porque
las sumas/restas arquitectónicas conservan los 32 bits bajos.

## Elecciones y alternativas

| Tema | Elección y razón | Alternativa descartada o futura |
|---|---|---|
| Lenguaje | Verilog-2005 sintetizable, estilo `.v` existente; prefijo tp3 para nuevos módulos | SystemVerilog de la referencia no se importa. `$fatal` es solo verificación y funciona en Icarus con `-g2005`. |
| Reloj/reset | 100 MHz previsto, posedge, reset síncrono alto | Sin flanco negativo ni clocks combinacionales. Cambio futuro solo con recursos dedicados y evidencia temporal. |
| RAM | 256 palabras por defecto, lectura combinacional, escritura síncrona, intención LUTRAM | BRAM síncrona cambia el contrato y requiere adaptar control/latencia. |
| Datos iniciales | Sin reset masivo en RAM; tests escriben antes de comparar | Limpiar RAM por recorrido secuencial explícito en etapa 5. |
| WB/ID | Bypass combinacional con enable; debug observa almacenamiento | Evita depender de dos flancos del reloj como la referencia. No constituye forwarding EX/MEM. |
| Burbuja | valid separado; reset/flush limpian datos y valid | Instrucción cero no se usa como sinónimo de NOP ni de validez. |
| Control de ALU | Una tabla de decoder y códigos internos; LUI por selector | Sin módulos para cada sumador/multiplexor simple. |
| Saltos | Clasificación ahora; comparación y redirección en EX después | No heredar resolución en ID de referencia. |
| Parada | EBREAK exacto 0x00100073, alias educativo HALT | ECALL y otros SYSTEM son ilegales; no adoptar HALT repetido de referencia. |
| Errores | Illegal y errores de dirección explícitos; controles seguros | Controlador ERROR y descarte de errores especulativos pendientes. |
| Debug | Lectura adicional banco/DMEM, PC e instruction en buses futuros | Capturar/serializar snapshots completos pertenece a etapa 5. |

## Políticas propuestas para integración (todavía no implementadas)

La carga requerirá núcleo detenido y pipeline vacío. Reiniciará PC al punto de
entrada (0 inicialmente), banco de registros y valid de las cuatro etapas.
Se registrarán longitud y entrada del programa. IMEM puede conservar palabras
posteriores a la longitud, pero fetch no podrá ejecutarlas; por eso no se necesita
vaciarla completa en cada carga. La política inicial de DMEM será limpieza
secuencial explícita al cargar, con una opción de conservación claramente indicada
al usuario. Un reset de ejecución conservará las RAM y limpiará PC/banco/pipeline;
estos comandos aún no existen.

STEP habilitará exactamente un ciclo del núcleo; la UART seguirá funcionando.
RUN usará habilitación continua. La pausa alcanzará PC, todos los registros,
escrituras WB y stores. Los snapshots se leerán con núcleo pausado, incluyendo
los 32 registros, los cuatro buses completos, PC, valid y estado. El rango de
memoria utilizada contemplará todos los bytes accedidos y un estado explícito
«sin accesos». No basta informar el último store.

La etapa 4 introducirá PAUSED/RUNNING/DRAINING/HALTED/ERROR o equivalentes.
HALT se consumirá una vez, no admitirá instrucciones posteriores y dejará completar
las anteriores. La parada normal requerirá todos los valid en cero. Un HALT
descartado por un salto anterior no podrá detener el núcleo. Si falta HALT, se
propondrá un límite configurable de ciclos: al agotarse, ERROR por cancelación
descarta el pipeline y conserva efectos ya comprometidos; no se anuncia finalización
normal. Las pruebas de etapa 4 deberán fijar con precisión la prioridad del último
ciclo permitido, redirecciones y errores de instrucciones jóvenes.

Setup/hold, camino crítico, skew y utilización se medirán en etapa 6. El retardo
de lógica entre registros no es el skew (diferencia de llegada del reloj).
Si hiciera falta otra frecuencia, se justificará con implementación Vivado y se
recalculará el divisor de UART; no se relajarán restricciones para ocultar errores.
