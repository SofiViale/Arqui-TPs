"""Tk integration checks; needs a graphical session, no FPGA. No automatic skip."""
import json
import sys
import time
import tkinter as tk
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'pc'))
from gui import DebugApp
from model import now
from demo import DemoTransport
from worker import SerialWorker

TP3 = Path(__file__).resolve().parents[1]


class WindowTests(unittest.TestCase):
    def setUp(self):
        self.root = tk.Tk()
        self.root.withdraw()
        self.transport = DemoTransport()
        self.worker = SerialWorker(factory=lambda port, demo: self.transport)
        self.app = DebugApp(self.root, demo=True, worker=self.worker, program=TP3 / 'programs/demo.asm')

    def tearDown(self):
        self.worker.close()
        self.worker.thread.join(2)
        try:
            self.root.destroy()
        except tk.TclError:
            pass

    def finish(self):
        deadline = time.monotonic() + 3
        while self.app.busy:
            self.root.update()
            self.assertLess(time.monotonic(), deadline)
            time.sleep(0.01)
        self.root.update()

    def click(self, name):
        self.assertEqual(str(self.app.buttons[name]['state']), 'normal', name)
        self.app.buttons[name].invoke()
        self.finish()

    def test_navigation_real_callbacks_export_reconnect(self):
        self.click('connect')
        self.assertTrue(self.app.verified)
        self.assertEqual(str(self.app.buttons['load']['state']), 'disabled')
        self.click('snapshot')  # establish empty pipeline before BEGIN
        self.click('load')
        self.assertEqual(len(self.app.reg_table.get_children()), 32)
        before = len(self.transport.commands)
        self.click('step')
        self.assertEqual(self.transport.commands[before:], [6, 9])
        self.assertEqual(self.app.evidence.capture['decoded']['header'][3], 1)
        self.click('run')
        self.assertEqual(str(self.app.buttons['step']['state']), 'disabled')
        self.assertIn('stale_reason', self.app.evidence.capture)
        time.sleep(0.4)
        self.app.perform('status', capture_terminal=True)
        self.finish()
        self.assertEqual(self.app.evidence.capture['decoded']['registers'][4], 19)
        self.assertEqual(self.app.evidence.memory['raw_hex'], '0c000000')
        self.click('memory')
        self.assertEqual(len(self.app.memory_table.get_children()), 4)
        for tab in self.app.tabs.tabs():
            self.app.tabs.select(tab)
            self.root.update()
        with TemporaryDirectory() as directory:
            path = Path(directory) / 'evidence.json'
            self.app.export(path)
            exported = json.loads(path.read_text(encoding='utf-8'))
            self.assertEqual(exported['source'], 'simulado')
            self.assertEqual(len(exported['snapshot']['decoded']['registers']), 32)
            self.assertIn('raw_hex', exported['memory'])
            self.assertTrue(exported['log'])
        self.click('disconnect')
        self.assertIn('stale_reason', self.app.evidence.capture)
        # A new simulated device session must not retain prior registers/memory.
        self.worker.factory = lambda port, demo: DemoTransport()
        self.click('connect')
        self.assertIsNone(self.app.evidence.capture)
        self.assertFalse(self.app.reg_table.get_children())
        self.assertIsNone(self.app.evidence.memory)

    def test_busy_errors_x0_and_draining_state(self):
        self.app.buttons['connect'].invoke()
        self.assertEqual(str(self.app.buttons['connect']['state']), 'disabled')
        self.assertEqual(str(self.app.buttons['step']['state']), 'disabled')
        self.finish()
        self.click('snapshot')
        s = self.app.evidence.capture['decoded']
        s['registers'] = [9] + [0] * 31
        self.app._render_snapshot(s)
        row = self.app.reg_table.get_children()[0]
        self.assertEqual(self.app.reg_table.item(row)['tags'], ['anomaly'])
        values = list(self.app.status_values)
        values[8], values[10] = 2 | 8 | (1 << 8), 999
        self.app.handle_event(dict(kind='status', at=now(), values=values))
        self.app._sync_actions()
        self.assertEqual(str(self.app.buttons['step']['state']), 'disabled')
        self.app.handle_event(dict(kind='error', at=now(), action='step', message='respuesta perdida', error_type='TimeoutError', uncertain=True))
        self.app._sync_actions()
        self.assertFalse(self.app.verified)
        self.assertEqual(str(self.app.buttons['run']['state']), 'disabled')
        self.assertEqual(str(self.app.buttons['status']['state']), 'normal')
        self.assertIn('incierto', self.app.operation.get())
        self.app.handle_event(dict(kind='error', at=now(), action='load', message='captura perdida',
                                   error_type='TimeoutError', uncertain=False, effect_acknowledged=True))
        self.assertIn('COMMIT confirmado', self.app.load_label.get())
        self.assertIn('ya recibió ACK', self.app.operation.get())

    def test_window_remains_responsive_and_closes_during_io(self):
        self.transport.read = lambda n: (time.sleep(0.01) or b'')
        self.app.buttons['connect'].invoke()
        heartbeat = []
        self.root.after(25, lambda: heartbeat.append(True))
        deadline = time.monotonic() + 1
        while not heartbeat:
            self.root.update()
            self.assertLess(time.monotonic(), deadline)
            time.sleep(0.01)
        self.assertTrue(self.app.busy)
        self.app.close()
        self.worker.thread.join(1)
        self.assertFalse(self.worker.thread.is_alive())
        self.assertTrue(self.transport.closed)
        self.root.update()  # drain shutdown events and destroy the window


if __name__ == '__main__':
    unittest.main()
