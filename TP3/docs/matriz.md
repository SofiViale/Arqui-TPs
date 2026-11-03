# Matriz de requisitos, implementación y pruebas

La prueba física de Basys 3 se registra por separado; ninguna fila de simulación la sustituye. Las comprobaciones históricas se vuelven a ejecutar mediante `regress.py`.

| Requisito | Implementación | Verificación |
|---|---|---|
| Conservar TP1/TP2, ALU única | sources.tcl, alu_adapter.v, system.v | git diff TP1 TP2 vacío; lista explícita de fuentes |
| Bloques previos | decoder/immediate/register_file/state/imem/dmem | alu/decode/register_file/state/memory_tb históricos |
| Pipeline previo conservado | core.v, arithmetic_system.v, sólo regresión | pipeline_tb histórico |
| Cinco etapas y 32 registros | processor.v | processor_tb, todos los registros por programa, RUN y STEP |
| Cada instrucción exigida | decoder.v y processor.v | test_cases.py: R/I, LUI, bytes, loop, JAL/JALR |
| x0 y x31 reales | register_file.v | successive_sources_x0, casos aritméticos con rd=x31, loop y UART |
| Forwarding ambas fuentes y prioridad | selectores EX processor.v | successive_sources_x0, wb_id, demo |
| Load-use por fuentes usadas | stall + uses_rs1/2 | demo, false_load_use, load_store_base_data; conteo exacto de stalls |
| Stores con base/dato dependientes | forwarding y XM.store_data | load_store_base_data, demo, neighbors |
| Bytes, signo y vecinos | máscaras y load_value | bytes, neighbors, last_byte; chequeo de toda DMEM |
| Validar dirección original y extensión | mem_align/mem_range | error_lw/lh/sw/sh, negativo y límite; memory_tb no potencia de dos |
| BEQ/BNE adelante/atrás, JAL/JALR | taken/target y flush EX | loop, load_branch, jalr_alu, jalr_load |
| Link PC+4 y limpieza bit0 JALR | ex_result y target | JAL con x31, JALR con direcciones impares |
| Descartar writes/HALT/ilegal | valid + flush + metadatos | flush_store_wb, flush_halt_illegal |
| Errores precisos y prioridad antigüedad | mem_bad > stop_ex | illegal_precise, mem_older_halt, error.asm |
| HALT y pipeline vacío | draining/terminal | todos los programas con HALT; halt_stops_store |
| Sin HALT / bucle infinito | longitud fetch + watchdog | no_halt, watchdog, watchdog_last_halt |
| STEP exacto, pausa y reset | enabled, reinicio y escrituras condicionadas | comparación RUN/STEP de todos los casos, pausa entre cada ciclo, PAUSE simult?neo con RUN/STEP y WB/store pendientes; reset con WB/store pendientes |
| UART RTL real y TX ocupado | módulos TP2 + packet.v | uart_system_tb, bytes consecutivos y decodificador independiente de TX; uart_baud_tb a 9600 baud con recuperaci?n de break/error de stop |
| CRC, escape, timeout y recuperación | packet.v y protocol.py | uart_vectors.py y test_host.py |
| Comandos desconocidos/longitudes/estados | debug.v | UART: unknown, RUN sin programa, STEP payload incorrecto, BEGIN ocupado, memoria inválida |
| Carga parcial y COMMIT | BEGIN/DATA/COMMIT | UART rechaza COMMIT/RUN incompletos |
| Reprogramación más corta | program_bytes y validación de fetch | UART demo → programa corto → programa sin HALT |
| Entrada/longitud e integridad | validaciones BEGIN/DATA | UART y validaciones host |
| Limpieza secuencial / conservación | CLEAR y flag preserve | UART lee DMEM después de restart 0/1 y nuevas cargas |
| Aplicación Windows | tp3.py, requirements.txt | test_host.py, ensamblado de ejemplos, --help; transporte físico pendiente |
| Etiquetas, registros y rangos | assembler.py | test_host.py: encodings conocidos y errores con línea |
| Snapshot coherente completo | pausa + captura debug.v | UART con pipeline ocupado y final; schema/anchos/padding/campos en test_host.py |
| Memoria utilizada | used_valid/lo/hi | bytes, demo y snapshots; rango incluye último byte |
| Top/reloj/reset/display | basys3_top.v | board_tb; síntesis/implementación en informe final |
| STEP sincronizado y antirrebote | step_button + contador estable | board_tb: rebotes, dos pulsaciones y pulsación sostenida |
| Pines y polaridades oficiales | constraints/basys3.xdc | Master XDC y manual Digilent enlazados en README |
| Flujo reproducible | sources/build/program.tcl | ejecución Vivado y reportes reales, ver verificacion_final.md |
| Primera prueba y reprogramación físicas | README + CLI | pendiente conectar placa y ejecutar checklist del README |

Los esperados de `test_cases.py` son valores literales, independientes de la ALU/decoder. El ensamblador sólo produce estímulos. Cada caso se ejecuta en RUN y STEP, y verifica x0..x31 y las 256 palabras de DMEM, incluidas las que deben permanecer en cero. Los anchos y flags del snapshot se contrastan con RTL, no se asumen a partir de un documento antiguo.
