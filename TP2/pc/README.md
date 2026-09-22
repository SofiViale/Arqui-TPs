# Calculadora de la ALU por UART

Interfaz de escritorio para enviar operandos a la ALU de la FPGA. Incluye teclado
numérico, selección de operandos A/B y botones **ADD, SUB, AND, OR, XOR, SRA, SRL
y NOR**. Pulsar una operación envía la solicitud y muestra la respuesta recibida.
El cálculo se realiza en la FPGA; la aplicación no sustituye la ALU por Python.

## Ejecutar desde VS Code

Desde **Terminal → Nueva terminal**, en la raíz del repositorio:

```powershell
python -m pip install -r TP2/pc/requirements.txt
python TP2/pc/calculator.py
```

Se necesita Python 3.9 o posterior con PySide6 y pyserial. En el entorno de
desarrollo ya estaban instalados PySide6 6.10.0 y pyserial 3.5; no se instalaron
dependencias durante este desarrollo. Si ya están disponibles, alcanza con el
segundo comando. También puede usarse `py -3` en lugar de `python`.

Para aislar las dependencias, opcionalmente:

```powershell
python -m venv TP2/pc/.venv
TP2/pc/.venv/Scripts/python.exe -m pip install -r TP2/pc/requirements.txt
TP2/pc/.venv/Scripts/python.exe TP2/pc/calculator.py
```

## Usar la calculadora

1. Programar la FPGA con el sistema `tp2_top` de TP2 y aplicar reset. La aplicación
   no genera ni carga un bitstream. La integración con Vivado sigue siendo una
   etapa separada.
2. Conectar la placa por USB y elegir el puerto correspondiente. **Actualizar**
   vuelve a buscar puertos; también se puede escribir uno manualmente.
3. Pulsar **Conectar**. La configuración es fija: **9600 baud, 8 bits, sin paridad,
   un stop y sin control de flujo**. Abrir un puerto no prueba por sí solo que la
   FPGA esté programada ni que responda.
4. Elegir el campo **A** e ingresar un número con el teclado físico o los botones.
   Usar **Editar B**, Tab o un clic para cambiar al segundo operando.
5. Pulsar uno de los ocho botones de operación. No hace falta presionar `=`.
6. Leer el resultado decimal sin signo, su binario de ocho bits, su hexadecimal y
   su interpretación con signo. La expresión arriba del resultado identifica los
   operandos que produjeron esa respuesta; editar los campos no recalcula ese
   resultado anterior.

**C** pone en cero el operando activo; **DEL** borra un dígito o la selección.
**Intercambiar A / B** invierte ambos operandos. El historial conserva las últimas
50 operaciones durante la sesión. La ventana permite desplazarse verticalmente
si la pantalla no tiene altura suficiente.

Los botones de operación permanecen deshabilitados hasta abrir un puerto y tener
dos operandos válidos. Durante una solicitud se bloquean nuevas operaciones y
ediciones; la ventana sigue procesando eventos. La comunicación ocurre en un hilo
separado y solamente ese hilo accede al puerto.

## Números de ocho bits

La entrada es **decimal sin signo entre 0 y 255**. Letras, signos y separadores
decimales no se aceptan al escribir. Si se ingresa `256`, `1000` u otro número
mayor que 255, el valor queda visible, se marca en rojo y se bloquea el envío.
No se recorta el dato, no se limita silenciosamente a 255 y no se aplica módulo
256 a la entrada. Un campo vacío también impide operar.

Los resultados sí tienen el comportamiento de ocho bits de la ALU original:

| Solicitud | Resultado sin signo | Binario | Con signo |
|---|---:|---|---:|
| `5 ADD 10` | 15 | `00001111` | 15 |
| `255 ADD 1` | 0 | `00000000` | 0 |
| `5 SUB 10` | 251 | `11111011` | -5 |
| `204 SRA 2` | 243 | `11110011` | -13 |
| `204 SRL 2` | 51 | `00110011` | 51 |

Para enviar un patrón negativo se ingresa su representación sin signo: `255`
representa también -1; `128`, -128. En SRA, el bit 7 de A es el signo. En ambos
desplazamientos, B completo indica la cantidad de posiciones; no se limita a 7.

## Protocolo compatible con el RTL

```text
PC → FPGA: CD | A | B | OP
FPGA → PC: resultado (un byte)
Ejemplo:   CD 05 0A 20 → 0F
```

Se transmiten bytes binarios, no los caracteres ASCII de los números. El usuario
no necesita escribir `CD` ni los códigos de operación: los agrega la aplicación.

| Botón | Operación de seis bits | Byte enviado |
|---|---|---|
| ADD | `100000` | `20` |
| SUB | `100010` | `22` |
| AND | `100100` | `24` |
| OR | `100101` | `25` |
| XOR | `100110` | `26` |
| SRA | `000011` | `03` |
| SRL | `000010` | `02` |
| NOR | `100111` | `27` |

Los dos bits superiores del byte OP son cero. Se recibe exactamente un byte,
incluidos `00`, `0A`, `0D` y `FF`; no se buscan saltos de línea ni terminadores.
El protocolo no devuelve flags de carry, overflow o zero.

Se espera una respuesta antes de permitir la siguiente solicitud. Si no llega en
1,5 segundos, falla la escritura, se desconecta el dispositivo o aparecen bytes
pendientes inesperados, se informa el error y se cierra la conexión. El resultado
se limpia para evitar mostrar un dato anterior como respuesta de la operación
fallida. No hay reenvíos automáticos.

Después de un error de comunicación, revisar la conexión, **aplicar reset a la
FPGA y volver a conectar**. Esto es necesario porque el protocolo actual no tiene
identificadores de solicitud ni timeout para comandos incompletos en el receptor.
Reabrir el puerto de la PC por sí solo no resetea la FSM de la FPGA. La apertura
vacía el buffer de recepción local, pero no reemplaza ese reset.

## Archivos y verificación

```text
TP2/pc/
├── calculator.py             # Ventana, botones e hilo de comunicación
├── protocol.py               # Validación, códigos y armado de solicitudes
├── serial_client.py          # Puerto 9600 8N1, envío, recepción y errores
├── requirements.txt
├── README.md
└── tests/test_calculator.py   # Pruebas con puerto simulado y GUI sin ventana visible
```

Para ejecutar las pruebas:

```powershell
python -B -m unittest discover -s TP2/pc/tests -v
```

El 22/09/2026 se ejecutaron **20 pruebas, todas aprobadas**. Cubren los ocho
códigos contra `TP1/src/alu.v`, la trama exacta, límites de entrada, los 256 bytes
posibles de respuesta, el teclado y botones, espera sin bloqueo de la ventana,
exclusión de solicitudes simultáneas, escritura parcial, timeout, desconexión,
respuesta inesperada y cierre de la ventana durante una lectura.

Las pruebas usan un puerto simulado y no abren puertos físicos. **La comunicación
real con la FPGA queda pendiente de comprobar con la placa programada.** Estos
resultados tampoco reemplazan las simulaciones HDL del TP2.

Referencias de las bibliotecas: [API de pyserial](https://pyserial.readthedocs.io/en/latest/pyserial_api.html)
para la configuración y timeouts del puerto, y [QThread de Qt](https://doc.qt.io/qtforpython-6/PySide6/QtCore/QThread.html)
para la ejecución separada de la comunicación.
