"""TP3 wire protocol. No serial dependency required for assembly/tests."""
import struct
VERSION = 1
SCHEMA = 0x33545031
MAX_PAYLOAD = 512
COMMANDS = dict(status=1, begin=2, data=3, commit=4, run=5, step=6,
                pause=7, restart=8, snapshot=9, memory=10, limit=11)
ERRORS = {0: 'OK', 1: 'comando desconocido', 2: 'longitud incorrecta',
          3: 'estado ocupado/incompatible', 4: 'rango/alineación inválidos',
          5: 'programa incompleto o inválido'}
def crc16(data):
    crc = 0xffff
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ (0xa001 if crc & 1 else 0)
    return crc

def frame(command, seq, payload=b''):
    if len(payload) > MAX_PAYLOAD:
        raise ValueError('payload demasiado grande')
    raw = struct.pack('<BBB H', VERSION, command, seq, len(payload)) + payload
    raw += struct.pack('<H', crc16(raw))
    return b'\x7e' + b''.join(bytes((0x7d, b ^ 0x20)) if b in (0x7d, 0x7e) else bytes((b,)) for b in raw) + b'\x7e'

class Parser:
    def __init__(self):
        self.reset()
    def reset(self):
        self.buf = bytearray(); self.active = False; self.escape = False
    def feed(self, data):
        packets = []
        for b in data:
            if b == 0x7e:
                raw = self.buf
                if self.active and not self.escape and len(raw) >= 7:
                    version, cmd, seq, size = struct.unpack('<BBB H', raw[:5])
                    if version == VERSION and size <= MAX_PAYLOAD and len(raw) == size + 7 and crc16(raw) == 0:
                        packets.append((cmd, seq, bytes(raw[5:-2])))
                self.buf = bytearray(); self.active = True; self.escape = False
            elif self.active:
                if b == 0x7d and not self.escape:
                    self.escape = True
                else:
                    self.buf.append(b ^ 0x20 if self.escape else b); self.escape = False
                    if len(self.buf) > MAX_PAYLOAD + 7:
                        self.reset()
        return packets
