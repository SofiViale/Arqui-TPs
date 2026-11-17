"""Shared synchronous UART client. One caller owns the transport at a time."""
import struct
import time

from protocol import COMMANDS, ERRORS, SCHEMA, Parser, frame
from snapshot import WIDTHS


class ResponseError(RuntimeError):
    """The board explicitly rejected a request; it did not execute it."""


class ProtocolError(RuntimeError):
    pass


class Client:
    def __init__(self, transport, baud=9600, cancelled=None):
        if baud <= 0:
            raise ValueError('baud debe ser positivo')
        self.transport = transport
        self.baud = baud
        self.seq = 0
        self.parser = Parser()
        self.cancelled = cancelled or (lambda: False)

    def timeout(self, packet_size):
        # Same conservative wire budget as the original CLI, including escaping.
        return 2 + 2 * (packet_size + 2 * 519 + 2) * 10 / self.baud

    def request(self, cmd, payload=b''):
        if self.cancelled():
            raise InterruptedError('operación cancelada; resultado pendiente incierto')
        command, seq = COMMANDS[cmd], self.seq
        self.seq = (seq + 1) & 255
        packet = frame(command, seq, payload)
        written = self.transport.write(packet)
        if written is not None and written != len(packet):
            raise OSError('escritura UART incompleta; resultado incierto')
        self.transport.flush()
        deadline = time.monotonic() + self.timeout(len(packet))
        while time.monotonic() < deadline:
            if self.cancelled():
                raise InterruptedError('operación cancelada; resultado pendiente incierto')
            for got_cmd, got_seq, body in self.parser.feed(self.transport.read(1)):
                if (got_cmd, got_seq) != (command | 0x80, seq):
                    continue
                if not body:
                    raise ProtocolError('respuesta inválida: falta status')
                if body[0]:
                    if len(body) != 1 or body[0] not in ERRORS:
                        raise ProtocolError('respuesta de error malformada')
                    raise ResponseError(ERRORS[body[0]])
                data = body[1:]
                expected = (44 if cmd == 'status' else 256 if cmd == 'snapshot'
                            else struct.unpack('<II', payload)[1] if cmd == 'memory' else 0)
                if len(data) != expected:
                    raise ProtocolError(f'respuesta {cmd} inválida: {len(data)} bytes, esperados {expected}')
                return data
        self.parser.reset()
        raise TimeoutError('UART sin respuesta válida (timeout, trama incompleta o CRC inválido); '
                           'no se reintenta la orden; consultar STATUS para recuperar')

    def status(self):
        values = struct.unpack('<11I', self.request('status'))
        if (values[0] != SCHEMA or tuple(values[4:8]) != WIDTHS or
                values[1:4] != (1024, 512, 128)):
            raise ProtocolError('RTL/aplicación incompatibles (schema/anchos/capacidades)')
        flags = values[8]
        if flags & ~0x70f or flags & 7 > 4 or (flags >> 8) & 255 > 7:
            raise ProtocolError('flags de STATUS inválidos')
        return values

    def load(self, words, entry=0, preserve=False, progress=None):
        from model import validate_program
        validate_program(words, entry)
        cap = self.status()
        raw = struct.pack('<' + 'I' * len(words), *words)
        self.request('begin', struct.pack('<IIB', len(raw), entry, bool(preserve)))
        if progress:
            progress(0, len(raw))
        for offset in range(0, len(raw), cap[3]):
            chunk = raw[offset:offset + cap[3]]
            self.request('data', struct.pack('<I', offset) + chunk)
            if progress:
                progress(offset + len(chunk), len(raw))
        self.request('commit')

    def memory(self, address, count):
        from model import validate_memory
        validate_memory(address, count)
        result = bytearray()
        for start in range(address, address + count, 128):
            result += self.request('memory', struct.pack('<II', start, min(128, address + count - start)))
        return bytes(result)
