# Protocolo UART TP3, versión 1

Todos los enteros multibyte, palabras de programa y resultados se transmiten **little-endian**. UART 8 bits, sin paridad, un stop (8N1), baud por defecto 9600. Un único emisor PC, una solicitud pendiente. No hay mensajes espontáneos ni reintentos automáticos: cada respuesta conserva el identificador de la solicitud.

## Framing e integridad

Trama física: `7e ESCAPE(cabecera || payload || crc16) 7e`.
Dentro del cuerpo, cada byte `7e` o `7d` se sustituye por `7d` seguido de `byte XOR 20`. No se escapan otros bytes. Un `7e` sin escapar finaliza la trama anterior y también permite resincronizar el comienzo; una trama vacía se ignora. Un escape pendiente seguido de delimitador invalida la trama anterior.

| Offset sin escape | Tamaño | Campo |
|---:|---:|---|
| 0 | 1 | Versión = 1 |
| 1 | 1 | Comando; respuesta = comando OR 0x80 |
| 2 | 1 | Identificador 0..255, reflejado por la respuesta |
| 3 | 2 | Longitud del payload, 0..512 |
| 5 | longitud | Payload |
| 5+longitud | 2 | CRC, byte bajo primero |

CRC-16/MODBUS: ancho 16, polinomio normal `0x8005`, reflejado `0xA001`, init `0xFFFF`, refin=true, refout=true, xorout=0. Cubre versión, comando, identificador, longitud y payload, **antes del escape**, excluyendo delimitadores. `CRC("123456789")=0x4B37`. El receptor procesa también los dos bytes de CRC y exige residuo cero.

Longitud total sin escape = payload+7. El parser admite hasta 512 bytes de payload; las solicitudes definidas usan como máximo 132. Una longitud de comando no válida produce status 2. Longitud física incorrecta, CRC erróneo, versión desconocida, overflow del buffer, escape inválido o error de stop UART descartan la trama **sin ejecutar ni responder**. No se puede confiar en el identificador de una trama dañada. La siguiente trama delimitada válida recupera la comunicación.

Timeout de recepción: `CLK_FREQ/4` ciclos sin byte recibido en una trama parcial (250 ms a 100 MHz). Descarta el parcial y espera nuevo delimitador. Un comando desconocido con CRC y estructura correctos sí recibe status 1. Una nueva solicitud enviada mientras se sirve/transmite otra se descarta; el host debe esperar su respuesta. Los bytes de una misma trama pueden ser consecutivos, sin pausas adicionales entre stop y start.

TX sólo presenta un pulso cuando UART no está busy y no hay un pulso anterior pendiente de aceptación. Mantiene el byte escapado hasta transmitir su segundo componente. CRC y longitud se calculan sobre datos sin escape.

Respuesta: el primer byte de payload siempre es `status`; los siguientes son los datos que describe la tabla. Una respuesta de error tiene sólo ese byte.

| Status | Significado |
|---:|---|
| 0 | Éxito |
| 1 | Comando desconocido |
| 2 | Longitud incorrecta |
| 3 | Estado incompatible / ocupado |
| 4 | Rango, alineación, offset u opción incorrectos |
| 5 | Programa inválido / carga incompleta |

El identificador correlaciona solicitudes, **no** implementa deduplicación. Reenviar STEP podría ejecutar un segundo ciclo. Después de un timeout, consultar STATUS y decidir explícitamente cómo recuperar. Una respuesta perdida no revierte una orden ya ejecutada. La CLI calcula su timeout como `2 + 2*(bytes_solicitud + 2*519 + 2)*10/baud` segundos, además de lecturas seriales de hasta 100 ms. Las transferencias de debug largas no usan un timeout fijo de un carácter.

## Comandos

`u32` significa unsigned little-endian; `u8`, un byte. Los datos de respuesta excluyen el byte status de la tabla anterior.

| Comando | Código | Solicitud | Respuesta / efecto |
|---|---:|---|---|
| STATUS | 01 | Vacía | 11 u32: schema, bytes RAM, max payload, max bloque, ancho FI, IX, XM, MW, flags, PC, ciclos |
| BEGIN | 02 | longitud:u32, entrada:u32, conservar:u8 | Invalida programa, reinicia núcleo; limpia DMEM salvo conservar=1 |
| DATA | 03 | offset:u32, 4..128 bytes de palabras | Escribe secuencialmente IMEM; offset debe coincidir con bytes ya recibidos |
| COMMIT | 04 | Vacía | Valida longitud total recibida, habilita programa y reinicia núcleo pausado |
| RUN | 05 | Vacía | Habilita ejecución continua |
| STEP | 06 | Vacía | Avanza exactamente un ciclo estando detenido |
| PAUSE | 07 | Vacía | Detiene el avance, sin vaciar pipeline |
| RESTART | 08 | conservar:u8 | Limpia PC/banco/pipeline/contadores; DMEM secuencial salvo conservar=1 |
| SNAPSHOT | 09 | Vacía | Pausa y devuelve 256 bytes coherentes |
| MEMORY | 0a | dirección:u32, cantidad:u32 | Pausa y devuelve 4..128 bytes, ambos campos alineados a 4 |
| LIMIT | 0b | ciclos:u32 | Cambia watchdog detenido; 0 deshabilita |

En STATUS, flags[2:0]=estado, bit3=program_valid, bits[15:8]=causa; otros bits cero. Schema=0x33545031, RAM=1024, max payload=512, max bloque=128, anchos=64/196/141/103. PC/ciclos/flags se capturan juntos; las capacidades son constantes.

BEGIN requiere !running y pipeline_empty. Longitud: 4..1024, múltiplo de 4; entrada múltiplo de 4 y menor que longitud; conservar sólo 0 o 1. La carga comienza en IMEM[0], no en entry. DATA requiere programa inválido y núcleo detenido/vacío; bloque completo múltiplo de 4 y sin exceder longitud. COMMIT no permite ejecutar carga parcial. No hay rollback: desde BEGIN aceptado hasta COMMIT válido, el programa es inválido aunque queden palabras antiguas. BEGIN nuevo puede reiniciar una carga interrumpida. RUN/STEP requieren programa válido y estado no terminal; STEP además requiere !running. RESTART puede cancelar ejecución o carga, pero no vuelve válido un programa incompleto ni borra IMEM.

El ACK de BEGIN/RESTART espera a que termine la limpieza; el de DATA espera a la última escritura; STEP espera al flanco que avanza. SNAPSHOT y MEMORY no restauran RUN automáticamente. Los pulsos locales se inhiben durante servicio y respuesta, preservando la captura.

## Snapshot, schema 0x33545031

Se transmite status=0 seguido de estos 256 bytes. Todos los campos enteros son little-endian. Los anchos físicos están verificados con las declaraciones de `processor.v` por `test_host.py`; las capacidades permiten comprobar la compatibilidad antes de cargar.

| Offset de datos (sin status) | Tipo | Contenido |
|---:|---|---|
| 0 | u32 | Schema |
| 4 | u32 | Estado 0 pausado, 1 RUN, 2 drenando, 3 finalizado, 4 error |
| 8 | u32 | PC de fetch |
| 12 | u32 | Ciclos habilitados |
| 16 | u32 | Causa 0..7, definida en README |
| 20 | u32 | PC de instrucción de parada/error; watchdog usa PC fetch |
| 24 | u32 | Valid: bit0 FI, bit1 IX, bit2 XM, bit3 MW |
| 28 | u32 | Bit0 error fetch FI, bit1 error fetch IX, bit2 illegal IX |
| 32 | u32 | used_valid |
| 36 | u32 | Menor byte accedido con éxito |
| 40 | u32 | Mayor byte accedido con éxito, inclusive |
| 44 | u32 | Longitud programa en bytes |
| 48 | u32 | Entrada |
| 52 | u32 | Límite de ciclos |
| 56 | u32 | running |
| 60 | u32 | program_valid |
| 64 | 32 u32 | x0..x31, en ese orden |
| 192 | 8 bytes | FI: 64 bits |
| 200 | 25 bytes | IX: 196 bits, 4 bits superiores de relleno cero |
| 225 | 18 bytes | XM: 141 bits, 3 bits superiores de relleno cero |
| 243 | 13 bytes | MW: 103 bits, bit superior de relleno cero |

Campos de **mayor a menor peso** dentro de cada bus:

- FI: pc:32, instruction:32.
- IX: pc:32, instruction:32, rs1:5, rs2:5, rd:5, operand1:32, operand2:32, immediate:32, uses_rs1:1, uses_rs2:1, alu_op:4, src_a:2, src_b_imm:1, reg_write:1, mem_read:1, mem_write:1, wb_sel:2, mem_size:2, load_unsigned:1, branch_type:3, is_halt:1.
- XM: pc:32, instruction:32, rd:5, result:32, store_data:32, reg_write:1, mem_read:1, mem_write:1, mem_size:2, load_unsigned:1, wb_from_mem:1, is_halt:1.
- MW: pc:32, instruction:32, rd:5, write_data:32, reg_write:1, is_halt:1.

Los operandos IX son los valores capturados en ID; forwarding se aplica al consumirlos en EX. XM.store_data ya contiene el operando actualizado, antes del desplazamiento de byte en MEM. Valid=0 hace irrelevantes los controles, aunque el payload conserve información. `exceptions` aporta los metadatos adicionales de FI/IX; no se ocultan en bits de padding. El formateador Python muestra todos los campos, incluso con valid=0.

## Ejemplo reproducible de intercambio

El código de producción permite generar las tramas exactas, incluidos CRC y escapes, sin puerto serial:

```powershell
py -c "import sys; sys.path.insert(0,'TP3/pc'); from protocol import frame; print(frame(1,0).hex(' '))"
```

La trama STATUS completa es `7e 01 01 00 00 00 18 3c 7e`. STATUS usa cuerpo `01 01 00 00 00` seguido de su CRC little-endian. La respuesta tiene comando `81`, identificador `00`, longitud `2d 00` y payload `00` + las once palabras. Para el ejemplo de seis instrucciones, BEGIN lleva payload `18 00 00 00 00 00 00 00 00`; DATA offset cero seguido de las seis palabras ensambladas; COMMIT, RUN y SNAPSHOT llevan payload vacío. `uart_vectors.py` genera y verifica estos intercambios reales por las señales RX/TX del RTL, además de cargas repetidas y errores.
