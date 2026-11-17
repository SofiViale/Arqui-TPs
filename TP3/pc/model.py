"""Validation, instruction representation and provenance, independent of Tk/serial."""
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

from assembler import assemble, R, I, LOAD, STORE


def now():
    return datetime.now(timezone.utc).isoformat()


def validate_program(words, entry=0):
    if not 1 <= len(words) <= 256:
        raise ValueError('IMEM admite 1..256 palabras (4..1024 bytes)')
    if entry % 4 or not 0 <= entry < len(words) * 4:
        raise ValueError('entrada en bytes: múltiplo de 4 y dentro del programa')
    if any(not isinstance(w, int) or not 0 <= w <= 0xffffffff for w in words):
        raise ValueError('palabra de instrucción fuera de uint32')


def read_program(path, entry=0):
    # The existing CLI accepts assembly source, not its assemble command's hex output.
    words = assemble(Path(path).read_text(encoding='utf-8-sig'))
    validate_program(words, entry)
    return words


def validate_memory(address, count):
    if address % 4 or count % 4 or count <= 0 or address < 0 or address + count > 1024:
        raise ValueError('DMEM: dirección y cantidad en bytes, múltiplos de 4; rango dentro de 0..1023')


def sext(value, bits):
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def instruction(word):
    """Strict inverse of supported encodings. None means unknown, including extensions."""
    op, f, g = word & 127, (word >> 12) & 7, word >> 25
    d, a, b = (word >> 7) & 31, (word >> 15) & 31, (word >> 20) & 31
    imm = sext(word >> 20, 12)
    name = None
    if word == 0x00100073:
        name = 'halt'
    elif op == 0x33:
        name = next((n for n, codes in R.items() if codes == (f, g)), None)
    elif op == 0x13:
        name = next((n for n, code in I.items() if code == f), None)
        if f == 1 and g == 0:
            name, imm = 'slli', b
        elif f == 5 and g in (0, 32):
            name, imm = ('srai' if g else 'srli'), b
    elif op == 3:
        name = next((n for n, code in LOAD.items() if code == f), None)
    elif op == 0x23:
        name = next((n for n, code in STORE.items() if code == f), None)
        imm = sext(((word >> 25) << 5) | ((word >> 7) & 31), 12)
    elif op == 0x63 and f in (0, 1):
        name = 'bne' if f else 'beq'
        imm = sext(((word >> 31) << 12) | (((word >> 7) & 1) << 11) |
                   (((word >> 25) & 63) << 5) | (((word >> 8) & 15) << 1), 13)
    elif op == 0x6f:
        name = 'jal'
        imm = sext(((word >> 31) << 20) | (((word >> 12) & 255) << 12) |
                   (((word >> 20) & 1) << 11) | (((word >> 21) & 1023) << 1), 21)
    elif op == 0x67 and f == 0:
        name = 'jalr'
    elif op == 0x37:
        name, imm = 'lui', word & 0xfffff000
    if name is None:
        return None
    return dict(name=name, rd=d, rs1=a, rs2=b, immediate=imm)


def disassemble(word):
    ins = instruction(word)
    if ins is None:
        return f'0x{word:08x} (desconocida)'
    n, d, a, b, v = (ins[k] for k in ('name', 'rd', 'rs1', 'rs2', 'immediate'))
    if word == 0x13:
        return 'nop (addi x0, x0, 0)'
    if n == 'halt':
        return 'halt (EBREAK)'
    if n in R:
        return f'{n} x{d}, x{a}, x{b}'
    if n in LOAD or n == 'jalr':
        return f'{n} x{d}, {v}(x{a})'
    if n in STORE:
        return f'{n} x{b}, {v}(x{a})'
    if n in ('beq', 'bne'):
        return f'{n} x{a}, x{b}, {v:+d} bytes'
    if n == 'jal':
        return f'jal x{d}, {v:+d} bytes'
    if n == 'lui':
        return f'lui x{d}, 0x{v >> 12:05x}'
    return f'{n} x{d}, x{a}, {v}'


@dataclass
class Evidence:
    source: str = 'sin conexión'
    session: str | None = None
    status: dict | None = None
    capture: dict | None = None
    memory: dict | None = None
    local_program: dict | None = None
    load_ack: dict | None = None
    log: list = field(default_factory=list)

    def invalidate(self, reason):
        for item in (self.status, self.capture, self.memory):
            if item:
                item['stale_reason'] = reason

    def new_session(self, source):
        self.source, self.session = source, now()
        self.status = self.capture = self.memory = self.load_ack = None

    def record(self, message):
        self.log.append(dict(at=now(), message=message, source=self.source, session=self.session))

    def export(self):
        return dict(format='TP3-GUI-1', exported_at=now(), source=self.source,
                    session_started_at=self.session, status=self.status, snapshot=self.capture,
                    memory=self.memory, local_program=self.local_program, load_ack=self.load_ack,
                    log=self.log, limitations=[
                        'SNAPSHOT pausa y es coherente internamente; STATUS y MEMORY tienen fechas independientes.',
                        'MEMORY por bloques no constituye un snapshot atómico con registros/pipeline; botones locales pueden intervenir entre órdenes.',
                        'IMEM no es legible; ACK de COMMIT no verifica por lectura el programa local.',
                        'PC es de fetch; stall, flush y selectores forwarding no se exponen.',
                        'Demostración Python no certifica timing ni funcionamiento en FPGA.' if self.source == 'simulado' else
                        'Datos UART recibidos; la validación física debe conservar evidencia de la placa.'])
