"""Explicit offline wire transport and educational cycle model. Never used as fallback.

This is test/demo software, not an RTL or physical timing certification. RUN is
deliberately slowed to 40 cycles/s so that pause and status can be demonstrated.
"""
import struct
import time

from assembler import R, I, LOAD, STORE
from model import instruction
from protocol import Parser, SCHEMA, frame
from snapshot import FIELDS, WIDTHS, signed32

MASK = 0xffffffff
ALU = dict(add=0, sub=1, and_=2, or_=3, xor=4, sll=5, srl=6, sra=7, slt=8, sltu=9)
ALU['and'], ALU['or'] = 2, 3


def decode(pc, word, regs):
    ins = instruction(word)
    result = {k: 0 for k, _ in FIELDS[1]}
    result.update(pc=pc, instruction=word, rs1=(word >> 15) & 31,
                  rs2=(word >> 20) & 31, rd=(word >> 7) & 31, mem_size=2)
    a, b = result['rs1'], result['rs2']
    result.update(operand1=regs[a], operand2=regs[b])
    if ins is None:
        return result, True
    n, imm = ins['name'], ins['immediate']
    result['immediate'] = imm & MASK
    if n == 'halt':
        result['is_halt'] = 1
    elif n in R or n in I or n in ('slli', 'srli', 'srai'):
        result.update(uses_rs1=1, uses_rs2=int(n in R), reg_write=1,
                      src_b_imm=int(n not in R), alu_op=ALU[n if n in R else 'sltu' if n == 'sltiu' else n[:-1]])
        # SRAI's immediate bus carries the full I immediate, including funct7.
        if n == 'srai':
            result['immediate'] = 0x400 | imm
    elif n in LOAD or n in STORE:
        result.update(uses_rs1=1, uses_rs2=int(n in STORE), reg_write=int(n in LOAD),
                      mem_read=int(n in LOAD), mem_write=int(n in STORE), src_b_imm=1,
                      wb_sel=int(n in LOAD), mem_size={'b': 0, 'h': 1, 'w': 2}[n[1]],
                      load_unsigned=int(n in ('lbu', 'lhu')))
    elif n in ('beq', 'bne', 'jal', 'jalr'):
        result.update(uses_rs1=int(n != 'jal'), uses_rs2=int(n in ('beq', 'bne')),
                      reg_write=int(n in ('jal', 'jalr')), src_a=int(n != 'jalr'),
                      src_b_imm=1, wb_sel=2 if n in ('jal', 'jalr') else 0,
                      branch_type={'beq': 1, 'bne': 2, 'jal': 3, 'jalr': 4}[n])
    elif n == 'lui':
        result.update(reg_write=1, src_a=2, src_b_imm=1, wb_sel=3)
    return result, False


class DemoCPU:
    def __init__(self):
        self.imem = bytearray(1024)
        self.dmem = bytearray(1024)
        self.length = self.entry = self.loaded = 0
        self.program_valid = False
        self.limit = 1000000
        self.restart()

    def restart(self):
        self.pc, self.cycles = self.entry, 0
        self.cause = self.fault_pc = 0
        self.running = self.draining = self.terminal = False
        self.regs = [0] * 32
        self.valid = [False] * 4
        self.stages = [{k: 0 for k, _ in fields} for fields in FIELDS]
        self.f_fault = self.x_fault = self.x_illegal = False
        self.used = False
        self.lo = self.hi = 0

    @property
    def state(self):
        return (3 if self.cause == 1 else 4) if self.terminal else 2 if self.draining else int(self.running)

    def cycle(self):
        if not self.program_valid or self.terminal:
            return
        old_pc = self.pc
        fi, ix, xm, mw = self.stages
        fv, xv, mv, wv = self.valid
        # ID observes WB bypass on this enabled edge.
        if wv and mw['reg_write'] and mw['rd']:
            self.regs[mw['rd']] = mw['write_data']
        new_ix, illegal = decode(fi['pc'], fi['instruction'], self.regs)

        def forwarded(reg, original):
            if reg == 0:
                return 0
            if mv and xm['reg_write'] and not xm['mem_read'] and xm['rd'] == reg:
                return xm['result']
            if wv and mw['reg_write'] and mw['rd'] == reg:
                return mw['write_data']
            return original

        a = forwarded(ix['rs1'], ix['operand1'])
        b = forwarded(ix['rs2'], ix['operand2'])
        aa = ix['pc'] if ix['src_a'] == 1 else 0 if ix['src_a'] == 2 else a
        bb = ix['immediate'] if ix['src_b_imm'] else b
        op = ix['alu_op']
        value = {0: lambda: aa + bb, 1: lambda: aa - bb, 2: lambda: aa & bb,
                 3: lambda: aa | bb, 4: lambda: aa ^ bb, 5: lambda: aa << (bb & 31),
                 6: lambda: aa >> (bb & 31), 7: lambda: signed32(aa) >> (bb & 31),
                 8: lambda: int(signed32(aa) < signed32(bb)), 9: lambda: int(aa < bb)}[op]() & MASK
        value = (ix['pc'] + 4) & MASK if ix['wb_sel'] == 2 else ix['immediate'] if ix['wb_sel'] == 3 else value
        br = ix['branch_type']
        taken = br in (3, 4) or br == 1 and a == b or br == 2 and a != b
        target = ((a + ix['immediate']) & ~1 if br == 4 else ix['pc'] + ix['immediate']) & MASK
        target_bad = taken and bool(target % 4)
        ex_bad = xv and (self.x_fault or self.x_illegal or target_bad)
        stop = xv and (ix['is_halt'] or ex_bad)
        addr, size = xm['result'], 1 << xm['mem_size']
        mem_align, mem_range = bool(addr % size), addr + size > 1024
        mem_bad = mv and (xm['mem_read'] or xm['mem_write']) and (mem_align or mem_range)
        read = 0
        if mv and (xm['mem_read'] or xm['mem_write']) and not mem_bad:
            self.lo = min(self.lo, addr) if self.used else addr
            self.hi = max(self.hi, addr + size - 1) if self.used else addr + size - 1
            self.used = True
            if xm['mem_write']:
                self.dmem[addr:addr + size] = (xm['store_data'] & ((1 << (8 * size)) - 1)).to_bytes(size, 'little')
            read = int.from_bytes(self.dmem[addr:addr + size], 'little', signed=not xm['load_unsigned']) & MASK
        new_mw = dict(pc=xm['pc'], instruction=xm['instruction'], rd=xm['rd'],
                      write_data=read if xm['mem_read'] else xm['result'],
                      reg_write=xm['reg_write'], is_halt=xm['is_halt'])
        new_xm = {k: ix[k] for k in ('pc', 'instruction', 'rd', 'reg_write', 'mem_read',
                                     'mem_write', 'mem_size', 'load_unsigned', 'is_halt')}
        new_xm.update(result=value, store_data=b, wb_from_mem=int(ix['wb_sel'] == 1))
        stall = xv and ix['mem_read'] and ix['rd'] and fv and (
            new_ix['uses_rs1'] and new_ix['rs1'] == ix['rd'] or
            new_ix['uses_rs2'] and new_ix['rs2'] == ix['rd'])
        next_valid = [fv, xv, bool(xv and not stop and not mem_bad), bool(mv and not mem_bad)]
        was_draining = self.draining
        if mem_bad or stop:
            self.draining = True
            next_valid[:2] = [False, False]
            self.cause = (4 if mem_align else 5) if mem_bad else 3 if self.x_fault else 2 if self.x_illegal else 6 if target_bad else 1
            self.fault_pc = xm['pc'] if mem_bad else ix['pc']
            self.f_fault = self.x_fault = self.x_illegal = False
        elif self.draining:
            next_valid[:2] = [False, False]
            if not mv and not wv:
                self.terminal, self.running, self.draining = True, False, False
        elif xv and taken:
            self.pc = target
            next_valid[:2] = [False, False]
            self.f_fault = self.x_fault = self.x_illegal = False
        elif stall:
            next_valid[1] = False
            self.x_fault = self.x_illegal = False
        else:
            next_valid[:2] = [True, fv]
            self.x_fault, self.x_illegal = self.f_fault, illegal
            self.f_fault = bool(self.pc % 4 or self.pc >= self.length or self.pc >= 1024)
            fi = dict(pc=self.pc, instruction=0 if self.f_fault else int.from_bytes(self.imem[self.pc:self.pc + 4], 'little'))
            self.pc = (self.pc + 4) & MASK
        self.cycles += 1
        if self.limit and self.cycles >= self.limit and not mem_bad and not ex_bad and not (was_draining and not mv and not wv):
            self.cause, self.fault_pc = 7, old_pc
            self.terminal, self.running, self.draining = True, False, False
            next_valid = [False] * 4
        self.stages, self.valid = [fi, new_ix, new_xm, new_mw], next_valid

    def snapshot(self):
        h = [SCHEMA, self.state, self.pc, self.cycles, self.cause, self.fault_pc,
             sum(int(v) << i for i, v in enumerate(self.valid)),
             int(self.f_fault) | int(self.x_fault) << 1 | int(self.x_illegal) << 2,
             int(self.used), self.lo, self.hi, self.length, self.entry, self.limit,
             int(self.running), int(self.program_valid)]
        raw = struct.pack('<16I32I', *h, *self.regs)
        for fields, width, values in zip(FIELDS, WIDTHS, self.stages):
            bus = 0
            for name, bits in fields:
                bus = (bus << bits) | (values[name] & ((1 << bits) - 1))
            raw += bus.to_bytes((width + 7) // 8, 'little')
        return raw


class DemoTransport:
    def __init__(self):
        self.cpu = DemoCPU()
        self.parser = Parser()
        self.output = bytearray()
        self.closed = False
        self.last_tick = time.monotonic()
        self.commands = []

    def _tick(self):
        current = time.monotonic()
        ticks = min(2000, int((current - self.last_tick) * 40))
        if ticks:
            self.last_tick = current
            for _ in range(ticks):
                if not self.cpu.running:
                    break
                self.cpu.cycle()

    def write(self, packet):
        if self.closed:
            raise OSError('transporte cerrado')
        self._tick()
        for command, seq, payload in self.parser.feed(packet):
            self.commands.append(command)
            code, data = self._command(command, payload)
            self.output += frame(command | 0x80, seq, bytes([code]) + data)
        return len(packet)

    def _command(self, cmd, p):
        c = self.cpu
        sizes = {1: 0, 2: 9, 4: 0, 5: 0, 6: 0, 7: 0, 8: 1, 9: 0, 10: 8, 11: 4}
        if cmd not in sizes and cmd != 3:
            return 1, b''
        if cmd in sizes and len(p) != sizes[cmd] or cmd == 3 and (len(p) < 8 or len(p) > 132 or len(p) % 4):
            return 2, b''
        if cmd == 1:
            return 0, struct.pack('<11I', SCHEMA, 1024, 512, 128, *WIDTHS,
                                  c.state | int(c.program_valid) << 3 | c.cause << 8, c.pc, c.cycles)
        if cmd == 2:
            length, entry, preserve = struct.unpack('<IIB', p)
            if c.running or any(c.valid):
                return 3, b''
            if not 0 < length <= 1024 or length % 4 or entry % 4 or entry >= length or preserve > 1:
                return 4, b''
            c.length, c.entry, c.loaded, c.program_valid = length, entry, 0, False
            c.restart()
            if not preserve:
                c.dmem[:] = bytes(1024)
        elif cmd == 3:
            offset = int.from_bytes(p[:4], 'little')
            if c.running or any(c.valid) or c.program_valid:
                return 3, b''
            if not c.length or offset != c.loaded or offset + len(p) - 4 > c.length:
                return 4, b''
            c.imem[offset:offset + len(p) - 4] = p[4:]
            c.loaded += len(p) - 4
        elif cmd == 4:
            if not c.length or c.loaded != c.length:
                return 5, b''
            if c.running or any(c.valid):
                return 3, b''
            c.program_valid = True
            c.restart()
        elif cmd in (5, 6):
            if not c.program_valid:
                return 5, b''
            if c.terminal or cmd == 6 and c.running:
                return 3, b''
            if cmd == 5:
                c.running = True
                self.last_tick = time.monotonic()
            else:
                c.cycle()
        elif cmd in (7, 9, 10):
            if cmd == 10:
                address, count = struct.unpack('<II', p)
                if address % 4 or not 0 < count <= 128 or count % 4 or address + count > 1024:
                    return 4, b''
            c.running = False
            if cmd == 9:
                return 0, c.snapshot()
            if cmd == 10:
                return 0, bytes(c.dmem[address:address + count])
        elif cmd == 8:
            if p[0] > 1:
                return 4, b''
            c.restart()
            if not p[0]:
                c.dmem[:] = bytes(1024)
        elif cmd == 11:
            if c.running:
                return 3, b''
            c.limit = int.from_bytes(p, 'little')
        return 0, b''

    def read(self, count):
        if self.closed:
            raise OSError('transporte cerrado')
        result = self.output[:count]
        del self.output[:count]
        return bytes(result)

    def flush(self):
        pass

    def close(self):
        self.closed = True

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()
