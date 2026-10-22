# Verificación de la etapa 1

Fecha: 07/10/2026. **Resultado: etapa 1 completada en simulación RTL**.
No quedan verificaciones esenciales de bloques sin ejecutar. La validación física
y temporal corresponde a etapa 6 y no se presenta como realizada.

## Entorno y reproducción

Windows/PowerShell, Python 3.12, Icarus Verilog 12.0 (devel), identificador
`s20150603-1539-g2693dd32b`. Inicialmente no se encontraron iverilog, vvp,
Verilator, Vivado o xsim en PATH; WSL informó que no estaba instalado.
Se descargó con autorización el paquete Windows
[`iverilog-v12-20220611-x64_setup.exe`](https://bleyer.org/icarus/) y se extrajo
mediante [innoextract 1.9](https://constexpr.org/innoextract/) en
`TP3/build/tools/icarus/app/`. No se ejecutó el instalador ni se cambió el PATH.
También se usó pypdf 6.19.0 en `TP3/build/python_deps` para leer los materiales;
no es dependencia de los tests. Esas herramientas y textos extraídos no se
versionan y el runner no los descarga automáticamente.

Comando efectivamente ejecutado desde la raíz:

```powershell
python TP3/scripts/simulate.py
```

Salida del resumen (`TP3/build/results.json`):

```json
{
  "alu_tb": "PASS",
  "decode_tb": "PASS",
  "register_file_tb": "PASS",
  "state_tb": "PASS",
  "memory_tb": "PASS"
}
```

El proceso devolvió 0. Se ejecutaron primero bancos individuales a medida que
se implementaron, y luego la batería completa. Se usa `-g2005 -Wall` con top e
includes explícitos; `-Wno-timescale` evita el aviso de la ALU original sin
alterar TP1. Los únicos avisos de compilación restantes informan que `always @*`
es sensible a todas las palabras del array de memoria: es lo esperado para una
lectura combinacional, no un latch ni un error de rango.

Para obtener los comandos completos de cada top sin generar archivos:

```powershell
python TP3/scripts/simulate.py --list
```

También se verificó `python ../scripts/simulate.py --list` desde `TP3/build`:
resuelve las mismas rutas absolutas a fuentes, includes y salidas. Puede indicarse
una instalación externa con `--iverilog <ruta> --vvp <ruta>`.

## Cobertura y resultados

| Categoría requerida | Testbench | Evidencia |
|---|---|---|
| 1. ALU adaptada | `alu_tb.v` | 66 checks: 10 operaciones, cero, negativos, extremos, overflow modular, SLT/SLTU, shifts 0/1/31 y bits altos en B; operación interna inválida. |
| 2. Decoder | `decode_tb.v` | 32 instrucciones + HALT; 32 variantes de índices y vector original por caso. Compara todos los campos y los 25 bits de control, incluidas fuentes reales. Barrido de funct7/funct3 inválidos R, funct7 de shifts I, funct3 LOAD/STORE/BRANCH/JALR y opcodes no soportados. ECALL, CSR/mutaciones de HALT rechazados. |
| 3. Inmediatos | `decode_tb.v` | I/S: cero, ±1, límites y patrones mixtos; B/J: límites, negativos y recorrido de bits para comprobar orden; U con 12 ceros bajos; SRAI/shamt y SLTIU negativo; selector no reconocido. |
| 4. Banco | `register_file_tb.v` | 229 checks: reset de todos, escritura/lectura x0..x31, habilitación, ambas fuentes, bypass coincidente/no coincidente, debug antes/después de flanco y reset sobre escritura. |
| 5. PC | `state_tb.v` | Reset inicial 0 y personalizado 0x100, captura, hold y prioridad reset. |
| 6. Registro genérico | `state_tb.v` | Anchos 7 y 73; las ocho combinaciones reset/flush/enable desde estado no cero; valid, invalid, hold, ausencia de cambio antes del flanco. 42 checks junto al PC. |
| 7. IMEM/DMEM | `memory_tb.v` | Profundidades 1, 3 y 256: 83/89/848 checks (1.020 total). Escritura explícita y lectura de cada palabra, extremos, reescritura, enables, las 16 máscaras, debug independiente, direcciones altas/sin alinear/fuera de rango, preservación ante escritura inválida. |
| 8. Integración pequeña | `decode_tb.v` | 18 vectores aritméticos: decoder + inmediato + selectores + ALU y selector LUI. Resultados numéricos conocidos, sin fetch ni banco escrito ni pipeline. |

`decode_tb` suma **5.280** comprobaciones para sus tres categorías.
Total de la batería: **6.637**. No se contabiliza un mensaje PASS como prueba:
cada check compara valores y falla con `$fatal(1)` incluso si la condición es X.

Los esperados de ALU/integración son constantes independientes. El decoder se
compara contra controles especificados por vector, no contra otro decoder del
diseño. Los tests de inmediatos codifican un desplazamiento numérico y comparan
la salida contra ese número; no llaman al generador para construir el esperado.
Las máscaras se comprueban mediante un valor esperado mantenido por el testbench.
No se presupone que la RAM no inicializada contiene cero.

Los bancos secuenciales aplican señales en negedge y comprueban después de
posedge+1 ns, sin carreras con las asignaciones no bloqueantes. Un consumidor
adicional comprueba que una lectura coincidente con escritura de RAM captura el
dato anterior en ese flanco, y que las salidas combinacionales luego ven el nuevo.
Todos los bancos tienen watchdog; el runner limita cada proceso a 60 segundos.

Se realizó además una prueba negativa temporal en `build/failure_probe.v`:
`check(0, "deliberate failure")` produjo FAIL y retorno **1** de vvp. Su log es
`build/failure_probe.log`. Esto valida el mecanismo de salida no cero; no es un
fallo del diseño ni forma parte de los 6.637 checks de la batería.

## Criterios de cierre y límites

| Criterio | Estado |
|---|---|
| TP1/TP2 inspeccionados, sin cambios | Cumplido; diff vacío en ambas carpetas. |
| Desarrollo nuevo exclusivamente TP3 | Cumplido; solo TP3 aparece como nuevo en Git. |
| Reutilización de ALU real, adaptación identificada | Cumplido; dependencia explícita a TP1 y tres operaciones complementarias. |
| Decoder, inmediato, banco, PC, registro y memorias | Cumplido según cobertura anterior. |
| Pruebas automáticas ejecutables | Cumplido; cinco tops, código 0 y checks aprobados. |
| Diseño, contratos, decisiones y seis etapas documentados | Cumplido; README y cuatro documentos. |
| No implementar etapas 2–6 | Cumplido; no existe núcleo/top, forwarding, saltos ejecutables, protocolo ni aplicación nuevos. |
| Preparar pausa, depuración y carga | Cumplido a nivel de interfaces y contratos; integración pendiente. |

No se ejecutaron síntesis, análisis formal, implementación Vivado, mediciones de
recursos/timing, pruebas físicas de UART ni ejecución de programas completos.
La intención de RAM distribuida y 100 MHz no es evidencia de inferencia o cierre
temporal. Tampoco se volvió a validar la batería de TP2; sus archivos y pruebas
permanecen intactos. La referencia aprobada por el usuario solo se inspeccionó.

El archivo exacto del capítulo recortado no estaba disponible. Se usaron las
páginas equivalentes del libro completo, como detalla
[decisiones](decisiones.md#fuentes-y-alcance-de-la-inspección).
