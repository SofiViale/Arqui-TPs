# Verificación de la GUI del TP3

Fecha local: **16 de noviembre de 2026**, America/Buenos_Aires. Algunas marcas UTC de los artefactos corresponden al 17 de noviembre. No se conectó una Basys 3; se distingue software, simulación RTL y validación física pendiente.

## Inspección previa y correspondencia con la consigna

Se revisaron README, documentación completa del TP3, CLI, ensamblador, protocolo, snapshot, pruebas host, programas, vectores UART y RTL vigente: `processor.v`, `decoder.v`, `debug.v`, `packet.v`, `system.v`, `basys3_top.v` y definiciones. No se encontraron AGENTS.md en el repositorio; las búsquedas en ancestros accesibles tampoco aportaron instrucciones adicionales.

El PDF **sí estaba disponible** en `D:/Descargas/TRABAJO FINAL 2026.pdf`: se extrajo el texto de sus 20 páginas y se inspeccionaron visualmente las filminas 13–17 renderizadas. Se revisaron todas las referencias a interfaz, depuración, carga, ejecución y observabilidad: páginas 2, 4–5 y 13–19. No se copia el PDF al repositorio. No se atribuyen al PDF los requisitos adicionales de implementación del pedido del usuario.

| Evidencia | Implementación |
|---|---|
| PDF p.2, p.13: interfaz e interacción creativa | GUI local, colores por etapa, cambios, leyenda y vistas de datos reales. |
| PDF p.14 y decoder.v | Subconjunto R/I/load/store/BEQ/BNE/JAL/JALR/LUI, no RV32I completo. HALT es la convención EBREAK exacto del proyecto. |
| PDF p.15: 32 registros, latches y memoria usada | Banco completo, cuatro buses con todos sus campos, cinco paneles por etapa y rango DMEM. IF sólo tiene PC expuesto. |
| PDF p.16: ASM, traducción y carga UART sin resíntesis | Ensamblador existente y BEGIN/DATA/COMMIT; validación, progreso ACK, políticas de limpieza y longitud IMEM documentadas. |
| PDF p.17: ciclo por paso y continuo | STEP de un ciclo con captura posterior; RUN con STATUS y captura al observar fin, sin pausar durante ejecución para refrescar. |
| PDF p.18–19: reloj, diseño y pruebas | No se altera RTL/reloj. La evidencia temporal del 3/11 conserva su alcance histórico; se documentan arquitectura y pruebas de PC. |

Discrepancias resueltas con código y pruebas:

- `arquitectura.md`, `plan_etapas.md` y partes históricas de `decisiones.md` describen integraciones pendientes de etapas 1–2. Sus avisos remiten al README y protocolo vigentes. El top usa `processor.v`; el `core.v` histórico no es el procesador final.
- La filmina 10 describe rd como origen del destino JAL. Ensamblador, RTL y pruebas implementan **PC de la instrucción + inmediato**, y PC+4 en rd. La GUI sigue esa implementación.
- STATUS no pausa; SNAPSHOT **y MEMORY sí pausan** y no restauran RUN (`debug.v`, comandos 9/10). Sus botones explicitan ese efecto.
- STATUS no expone pipeline_empty ni running independiente en drenaje. Se exige captura reciente para habilitar carga y no se infiere que estado 2 está detenido. SNAPSHOT sí transmite valid/running.
- Stall, flush y selectores forwarding existen internamente pero no se serializan; se muestran como no disponibles. No hay lectura de IMEM ni escritura DMEM por UART.

## Entorno y comandos ejecutados

Windows, Python **3.12.2**, Tcl/Tk **8.6**, pyserial **3.5**, Icarus **12.0 devel s20150603-1539-g2693dd32b**, copia ya presente. El lanzador `py` del entorno aislado no detectó Python; se usó el ejecutable `python` instalado. La guía conserva los comandos solicitados con `py` para instalaciones normales de Windows.

```powershell
python -m unittest discover -s TP3/scripts -p "test_*.py" -v
python TP3/scripts/regress.py --simulator icarus
python TP3/pc/tp3.py --help
python TP3/pc/gui.py --help
python TP3/pc/tp3.py assemble TP3/programs/demo.asm
```

Todos finalizaron con código 0.

| Grupo | Resultado y cobertura |
|---|---|
| test_host.py | **11 PASS**, existentes: ensamblador, CRC, framing, schema y anchos RTL. |
| test_gui.py | **18 PASS**: validación ASM/rangos, desensamblado, CLI compartida, bytes parciales/escapados, secuencia incorrecta, respuestas inválidas, CRC/truncamiento, timeout y recuperación sin reintento, desconexión simulada, escritura corta, cancelación, cola y único hilo, pérdida ACK DATA sin COMMIT, cierre fallido/reconexión. |
| Modelo demo | Dentro de esos 18 tests: **50 programas dirigidos** con esperados literales de test_cases.py; compara x0..x31, toda DMEM y causa final. También ciclos de demo.asm, load-use, drenaje, estados terminales, carga parcial y conservación. No acredita equivalencia formal del modelo ni hardware. |
| test_gui_window.py | **3 PASS**, sin skips: Tk real y callbacks, conexión/carga/STEP/RUN/memoria, cinco pestañas, exportación JSON, reconexión limpia, anomalía x0, habilitación de acciones y ventana responsiva/cierre con I/O pendiente. |
| Regresión RTL | **10 bancos PASS**: seis históricos y processor/uart_system/uart_baud/board. **52.433 checks** en los siete bancos con conteo; UART se informa aparte: 69 intercambios, 3.582 bytes de respuestas y prueba a 9600 baud. |
| CLI / GUI help y ASM | Código 0; las seis palabras demo esperadas. tp3.Client reexporta la clase compartida. |
| Compatibilidad sintáctica | Los 12 archivos de PC, pruebas GUI y runner se analizaron con gramática Python 3.10. Ejecución efectiva en 3.12.2; otras versiones no se ejecutaron. |

El runner existente admite `--simulator icarus` además de xsim, cuyo comportamiento por defecto se conserva. Se genera una unidad temporal bajo `build/icarus/` que preserva las palabras clave Verilog-2005 del RTL y usa SystemVerilog para las assertions de los bancos. Así `sequence`, identificador válido del RTL, no se interpreta como palabra reservada SV. Un primer intento local de compilar todo como SV falló por esa razón; no se editó RTL para corregirlo. Los resultados se guardan separados de xsim en `build/regression_icarus.json` y `build/icarus/<banco>/`.

Tk dentro del sandbox no encontró un init.tcl usable. La batería con ventanas se ejecutó fuera del aislamiento, con la instalación existente y autorización, y pasó completa. Se corrigió la cancelación de callbacks after al destruir ventanas; la última ejecución no emite advertencias de callbacks Tcl pendientes.

## Prueba visual ejecutada

Se abrió `gui.py --demo --program TP3/programs/demo.asm` en el escritorio de Windows y se navegaron controles reales. Se observó la marca permanente de demostración, conexión verificada, captura inicial, ASM/desensamblado, COMMIT, un STEP (ciclo 1, PC=4), RUN y actualización automática al terminar. Se revisaron las cinco pestañas, registros x1=7, x2=x3=12, x4=19 resaltados, memoria `0c 00 00 00` y log. Se cerró la ventana y se comprobó que desapareció. La exportación se comprobó además con los callbacks reales en la prueba Tk.

## Evidencia conservada

[Resumen y hashes](evidence/2026-11-16/verification.json), [pruebas Python](evidence/2026-11-16/python_tests.log), [regresión RTL](evidence/2026-11-16/regression_icarus.json), [exportación simulada](evidence/2026-11-16/demo_export.json) y diez logs RTL en el mismo directorio. El ejemplo se obtuvo del cliente y transporte simulados con el formato del modelo de evidencia; no es una captura de placa.

## Archivos y alcance

| Archivos creados | Propósito |
|---|---|
| pc/client.py | Cliente compartido: protocolo, longitudes/capacidades y cancelación. |
| pc/model.py | Validaciones, desensamblado, procedencia y exportación. |
| pc/worker.py | Cola serial y dueño único del transporte. |
| pc/gui.py | Ventana tkinter/ttk en español. |
| pc/demo.py | Transporte de tramas y modelo educativo explícito. |
| scripts/test_gui.py, scripts/test_gui_window.py | Regresión de protocolo/modelo/cola y de Tk. |
| docs/gui.md, docs/verificacion_gui.md, docs/evidence/2026-11-16/* | Guía, resultados, correspondencia y evidencia. |

Modificados: `pc/tp3.py` importa el cliente compartido y conserva comandos; `pc/snapshot.py` valida flags booleanos y corrige un mensaje; `scripts/regress.py` agrega el motor Icarus; `README.md`, `docs/matriz.md` y `docs/verificacion_final.md` enlazan esta entrega. No se modifican TP1, TP2, RTL, constraints, baudrate ni framing UART.

## Verificación pendiente en Basys 3

Sólo se enumeró **COM1, puerto de comunicaciones del equipo**; no se identificó una Basys 3 ni se abrió ese puerto. No se ejecutó JTAG ni UART física. La demo no se activó como recuperación de fallos reales.

Ejecutar la prueba manual de siete pasos de [la guía](gui.md#prueba-manual-reproducible), guardar JSON de origen real y comparar banco/DMEM/ciclos/valid de demo.asm. Repetir loop, bytes, error, entry distinto de cero, limpiar/conservar y carga corta. Probar cable retirado, puerto ocupado, pausa durante RUN, reset/botón local entre consultas y cierre durante carga con recuperación por STATUS. Los fakes y la demo no sustituyen esas pruebas físicas. No se resintetizó ni se presentan nuevas métricas temporales en esta entrega de software.
