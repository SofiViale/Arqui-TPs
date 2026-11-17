"""Protocol/model/worker regression without a display or serial hardware."""
import json
import io
import contextlib
import queue
import struct
import sys
import threading
import time
import unittest
from unittest.mock import patch
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'pc'))
from assembler import assemble, AssemblyError
from client import Client, ProtocolError, ResponseError
from demo import DemoTransport
from model import Evidence, disassemble, instruction, read_program, validate_memory, validate_program
from protocol import COMMANDS, Parser, SCHEMA, frame
from snapshot import snapshot, signed32
from worker import SerialWorker
from test_cases import CASES

TP3 = Path(__file__).resolve().parents[1]


class ModelTests(unittest.TestCase):
    def test_program_validation_before_begin(self):
        for words, entry in [([], 0), ([0] * 257, 0), ([0], -4), ([0], 2), ([0], 4), ([-1], 0), ([1 << 32], 0)]:
            with self.subTest(entry=entry, size=len(words)), self.assertRaises(ValueError):
                validate_program(words, entry)
        validate_program([0] * 256, 1020)
        with self.assertRaises(AssemblyError):
            read_program(TP3 / 'README.md')
        t = DemoTransport()
        with self.assertRaises(ValueError):
            Client(t).load([0] * 257)
        self.assertEqual(t.commands, [])

    def test_memory_bounds(self):
        for address, count in [(-4, 4), (1, 4), (0, 0), (0, -4), (0, 6), (1020, 8), (2 ** 32, 4)]:
            with self.subTest(address=address, count=count), self.assertRaises(ValueError):
                validate_memory(address, count)
        validate_memory(1020, 4)
        validate_memory(0, 1024)

    def test_disassembly_strict_and_immediates(self):
        for source, expected in [('addi x1,x0,-1', 'addi x1, x0, -1'), ('sltiu x2,x1,-1', 'sltiu x2, x1, -1'),
                                 ('srai x31,x1,31', 'srai x31, x1, 31'), ('sw x2,-4(x1)', 'sw x2, -4(x1)'),
                                 ('beq x1,x2,-4', 'beq x1, x2, -4 bytes'), ('jal x31,8', 'jal x31, +8 bytes')]:
            self.assertEqual(disassemble(assemble(source)[0]), expected)
        for w in (0, 0xffffffff, 0x02000033, 0x00000073, 0x02001013, 0x00002063):
            self.assertIsNone(instruction(w))
            self.assertIn(f'{w:08x}', disassemble(w))
        self.assertIn('nop', disassemble(0x13))

    def test_provenance_and_export(self):
        e = Evidence()
        e.new_session('simulado')
        e.capture = dict(at='2026-11-16T00:00:00+00:00', raw_hex='00')
        e.invalidate('RUN')
        e.record('Prueba')
        exported = json.loads(json.dumps(e.export()))
        self.assertEqual(exported['source'], 'simulado')
        self.assertEqual(exported['snapshot']['stale_reason'], 'RUN')
        self.assertIn('coherente', exported['limitations'][0])
        e.new_session('UART real')
        self.assertIsNone(e.capture)
        self.assertIsNone(e.load_ack)


class AlteredTransport(DemoTransport):
    def __init__(self, change):
        super().__init__()
        self.change = change

    def write(self, packet):
        size = super().write(packet)
        replies = Parser().feed(self.output)
        self.output.clear()
        for cmd, seq, body in replies:
            self.output += self.change(cmd, seq, body)
        return size

    def read(self, count):
        if not self.output:
            time.sleep(0.001)
        return super().read(min(1, count))


class ClientTests(unittest.TestCase):
    def test_cli_still_uses_shared_client(self):
        import tp3
        self.assertIs(tp3.Client, Client)
        t = DemoTransport()
        # pyserial is optional for the offline tests; supply only its constructor.
        import types
        serial = types.SimpleNamespace(Serial=lambda *a, **kw: t)
        with patch.dict(sys.modules, serial=serial), contextlib.redirect_stdout(io.StringIO()) as out:
            code = tp3.main(['--port', 'SIMULADO', 'load', str(TP3 / 'programs/demo.asm')])
        self.assertEqual(code, 0)
        self.assertIn('6 instrucciones', out.getvalue())
        self.assertEqual(t.commands, [1, 1, 2, 3, 4])

    def test_partial_escaped_response_and_sequence(self):
        t = AlteredTransport(lambda cmd, seq, body: frame(cmd, (seq - 1) & 255, body) + frame(cmd, seq, body))
        c = Client(t)
        c.seq = 0x7e
        self.assertEqual(c.status()[0], SCHEMA)
        self.assertEqual(t.commands, [1])
        c.load([0x7e7d7e7d, 0x00100073])
        self.assertEqual(bytes(t.cpu.imem[:4]), bytes.fromhex('7d7e7d7e'))

    def test_malformed_lengths_errors_and_schema(self):
        for change in (lambda cmd, seq, body: frame(cmd, seq),
                       lambda cmd, seq, body: frame(cmd, seq, body[:-1]),
                       lambda cmd, seq, body: frame(cmd, seq, b'\x09'),
                       lambda cmd, seq, body: frame(cmd, seq, b'\x03x')):
            with self.assertRaises(ProtocolError):
                Client(AlteredTransport(change)).status()
        with self.assertRaises(ResponseError):
            Client(AlteredTransport(lambda cmd, seq, body: frame(cmd, seq, b'\x03'))).status()
        with self.assertRaises(ProtocolError):
            Client(AlteredTransport(lambda cmd, seq, body: frame(cmd, seq, body[:1] + bytes(4) + body[5:]))).status()

    def test_timeout_crc_incomplete_and_recovery_no_retry(self):
        for transform in (lambda packet: packet[:-3],
                          lambda packet: packet[:-2] + bytes([packet[-2] ^ 1]) + packet[-1:]):
            t = AlteredTransport(lambda cmd, seq, body: transform(frame(cmd, seq, body)))
            c = Client(t)
            c.timeout = lambda size: 0.005
            with self.assertRaises(TimeoutError):
                c.request('pause')
            self.assertEqual(t.commands, [7])
            t.change = lambda cmd, seq, body: frame(cmd, seq, body)
            self.assertEqual(c.status()[0], SCHEMA)
            self.assertEqual(t.commands, [7, 1])

    def test_unplug_short_write_and_cancellation(self):
        t = DemoTransport()
        t.close()
        with self.assertRaises(OSError):
            Client(t).status()
        t = DemoTransport()
        t.write = lambda packet: 1
        with self.assertRaises(OSError):
            Client(t).status()
        with self.assertRaises(InterruptedError):
            Client(DemoTransport(), cancelled=lambda: True).status()

    def test_memory_chunk_lengths(self):
        c = Client(DemoTransport())
        self.assertEqual(len(c.memory(0, 1024)), 1024)
        self.assertEqual(c.transport.commands, [10] * 8)
        c = Client(AlteredTransport(lambda cmd, seq, body: frame(cmd, seq, body[:-1])))
        with self.assertRaises(ProtocolError):
            c.memory(0, 4)


class DemoTests(unittest.TestCase):
    def test_all_directed_programs_reference_results(self):
        # Reuse independent literal expected results, not this demo's decoder.
        for case in CASES:
            with self.subTest(case=case['name']):
                src = case['asm']
                words = assemble(src.replace('.wordbad', 'nop'))
                for i, line in enumerate(src.splitlines()):
                    if '.wordbad' in line:
                        words[i] = 0xffffffff
                c = Client(DemoTransport())
                c.load(words)
                c.request('limit', struct.pack('<I', case['limit']))
                for _ in range(1001):
                    if c.transport.cpu.terminal:
                        break
                    c.request('step')
                s = snapshot(c.request('snapshot'))
                self.assertEqual(s['header'][4], case['cause'])
                self.assertEqual(s['header'][6], 0)
                self.assertEqual(list(s['registers']), [case['regs'].get(i, 0) & 0xffffffff for i in range(32)])
                mem = c.memory(0, 1024)
                self.assertEqual(list(struct.unpack('<256I', mem)), [case['mem'].get(i, 0) & 0xffffffff for i in range(0, 1024, 4)])

    def test_pipeline_demo_cycle_observations(self):
        c = Client(DemoTransport())
        c.load(read_program(TP3 / 'programs/demo.asm'))
        observations = []
        for _ in range(11):
            c.request('step')
            observations.append(snapshot(c.request('snapshot')))
        self.assertEqual([s['header'][2] for s in observations[:7]], [4, 8, 12, 16, 20, 20, 24])
        self.assertEqual(observations[0]['registers'][1], 0)
        self.assertEqual(observations[4]['registers'][1], 7)
        self.assertEqual(observations[5]['header'][6], 13)  # load-use bubble in EX
        self.assertEqual(observations[-1]['header'][1], 3)
        self.assertEqual(observations[-1]['registers'][4], 19)

    def test_restart_preserve_incomplete_load_and_terminal_reject(self):
        c = Client(DemoTransport())
        c.load(assemble('addi x1,x0,7\nsw x1,0(x0)\nhalt'))
        while not c.transport.cpu.terminal:
            c.request('step')
        with self.assertRaises(ResponseError):
            c.request('step')
        c.request('restart', b'\x01')
        self.assertEqual(c.memory(0, 4), b'\x07\x00\x00\x00')
        c.request('restart', b'\x00')
        self.assertEqual(c.memory(0, 4), bytes(4))
        c.request('begin', struct.pack('<IIB', 8, 0, 0))
        c.request('data', struct.pack('<II', 0, 0x13))
        with self.assertRaises(ResponseError):
            c.request('commit')
        self.assertFalse(c.status()[8] & 8)


def operation(worker, action, **args):
    worker.submit(action, **args)
    events = []
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        event = worker.events.get(timeout=2)
        events.append(event)
        if event['kind'] == 'done':
            return events
    raise AssertionError(f'worker no terminó {action}')


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.transport = DemoTransport()
        self.worker = SerialWorker(factory=lambda port, demo: self.transport)

    def tearDown(self):
        self.worker.close()
        self.worker.thread.join(2)
        self.assertFalse(self.worker.thread.is_alive())

    def test_connect_load_step_run_terminal_memory_and_disconnect(self):
        events = operation(self.worker, 'connect', port='SIMULADO', demo=True)
        self.assertEqual([e['kind'] for e in events], ['opened', 'status', 'done'])
        operation(self.worker, 'load', words=read_program(TP3 / 'programs/demo.asm'), entry=0, preserve=False)
        before = len(self.transport.commands)
        events = operation(self.worker, 'step')
        self.assertEqual(self.transport.commands[before:], [6, 9])
        self.assertEqual(next(e for e in events if e['kind'] == 'snapshot')['decoded']['header'][3], 1)
        before = len(self.transport.commands)
        operation(self.worker, 'run')
        self.assertEqual(self.transport.commands[before:], [5, 1])  # no implicit pause during RUN
        time.sleep(0.4)
        events = operation(self.worker, 'status', capture_terminal=True)
        self.assertIn('memory', [e['kind'] for e in events])
        final = next(e for e in events if e['kind'] == 'snapshot')
        self.assertEqual(final['decoded']['registers'][4], 19)
        before = len(self.transport.commands)
        operation(self.worker, 'disconnect')
        self.assertTrue(self.transport.closed)
        self.assertEqual(len(self.transport.commands), before)  # no PAUSE on disconnect

    def test_serialized_queue_and_single_thread_owner(self):
        owner_ids = []
        original = self.transport.write
        entered, release = threading.Event(), threading.Event()

        def blocking_write(packet):
            owner_ids.append(threading.get_ident())
            if len(owner_ids) == 1:
                entered.set()
                release.wait(2)
            return original(packet)

        self.transport.write = blocking_write
        self.worker.submit('connect', port='SIMULADO', demo=True)
        self.assertTrue(entered.wait(1))
        self.worker.submit('status')
        with self.assertRaises(queue.Full):
            self.worker.submit('status')
        release.set()
        self.worker.operations.join()
        self.assertEqual(self.transport.commands, [1, 1])
        self.assertEqual(set(owner_ids), {self.worker.thread.ident})

    def test_close_during_incomplete_response(self):
        self.transport.read = lambda n: (time.sleep(0.01) or b'')
        self.worker.submit('connect', port='SIMULADO', demo=True)
        while self.worker.events.get(timeout=1)['kind'] != 'opened':
            pass
        self.worker.close()
        self.worker.thread.join(1)
        self.assertFalse(self.worker.thread.is_alive())
        self.assertTrue(self.transport.closed)

    def test_load_lost_ack_not_retried_and_progress_not_commit(self):
        operation(self.worker, 'connect', port='SIMULADO', demo=True)
        original = self.transport.write

        def drop_data_ack(packet):
            result = original(packet)
            if self.transport.commands[-1] == COMMANDS['data']:
                self.transport.output.clear()
            return result

        self.transport.write = drop_data_ack
        self.worker.client.timeout = lambda n: 0.005
        events = operation(self.worker, 'load', words=[0x13, 0x00100073], entry=0, preserve=False)
        error = next(e for e in events if e['kind'] == 'error')
        self.assertTrue(error['uncertain'])
        self.assertEqual(self.transport.commands.count(3), 1)
        self.assertNotIn(4, self.transport.commands)
        self.assertNotIn('loaded', [e['kind'] for e in events])
        self.assertFalse(self.transport.cpu.program_valid)
        # A lost follow-up snapshot must not erase the known COMMIT acknowledgement.
        def drop_snapshot(packet):
            result = original(packet)
            if self.transport.commands[-1] == COMMANDS['snapshot']:
                self.transport.output.clear()
            return result
        self.transport.write = drop_snapshot
        events = operation(self.worker, 'load', words=[0x13, 0x00100073], entry=0, preserve=False)
        self.assertIn('loaded', [e['kind'] for e in events])
        error = next(e for e in events if e['kind'] == 'error')
        self.assertTrue(error['effect_acknowledged'])
        self.assertFalse(error['uncertain'])
        self.assertTrue(self.transport.cpu.program_valid)

    def test_close_failure_does_not_kill_owner_or_block_reconnection(self):
        operation(self.worker, 'connect', port='SIMULADO', demo=True)
        self.transport.close = lambda: (_ for _ in ()).throw(OSError('USB retirado'))
        events = operation(self.worker, 'disconnect')
        self.assertIn('close_warning', [e['kind'] for e in events])
        self.assertTrue(self.worker.thread.is_alive())
        self.worker.factory = lambda port, demo: DemoTransport()
        events = operation(self.worker, 'connect', port='SIMULADO', demo=True)
        self.assertIn('status', [e['kind'] for e in events])


if __name__ == '__main__':
    unittest.main()
