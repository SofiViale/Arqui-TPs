"""Single serial owner. All events contain plain data, never Tk objects."""
import queue
import struct
import threading

from client import Client, ResponseError
from model import now
from snapshot import snapshot


class SerialWorker:
    def __init__(self, factory=None):
        self.factory = factory or self.open_transport
        self.operations = queue.Queue(maxsize=1)
        self.events = queue.Queue()
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._loop, name='TP3-UART', daemon=True)
        self.client = None
        self.thread.start()

    @staticmethod
    def open_transport(port, demo):
        if demo:
            from demo import DemoTransport
            return DemoTransport()
        import serial
        try:
            return serial.Serial(port=port, baudrate=9600, bytesize=8, parity='N', stopbits=1,
                                 timeout=0.1, write_timeout=1, xonxoff=False, rtscts=False, dsrdtr=False)
        except OSError as error:
            raise OSError(f'No se pudo abrir {port}: puerto ocupado, sin permisos o desconectado. {error}') from error

    def submit(self, action, **arguments):
        self.operations.put_nowait((action, arguments))

    def close(self):
        # Never close the port from Tk's thread while another thread is reading it.
        self.stop.set()

    def emit(self, kind, **data):
        self.events.put(dict(kind=kind, at=now(), **data))

    def _disconnect(self):
        if self.client:
            try:
                self.client.transport.close()
            except Exception as error:
                self.emit('close_warning', message=f'Error al cerrar puerto: {error}')
            finally:
                self.client = None

    def _status(self, capture_terminal=False):
        values = self.client.status()
        self.emit('status', values=values)
        if capture_terminal and values[8] & 7 in (3, 4):
            self._snapshot(include_used=True)

    def _snapshot(self, include_used=False):
        raw = self.client.request('snapshot')
        decoded = snapshot(raw)
        self.emit('snapshot', raw=raw.hex(), decoded=decoded)
        h = decoded['header']
        if include_used and h[8]:
            start, end = h[9] & ~3, (h[10] + 4) & ~3
            self._memory(start, end - start)
        return decoded

    def _memory(self, address, count):
        raw = self.client.memory(address, count)
        self.emit('memory', address=address, raw=raw.hex(),
                  coherence='lectura separada; MEMORY pausa; varios bloques no son atómicos')

    def _execute(self, action, args):
        if action == 'connect':
            self._disconnect()
            transport = self.factory(args['port'], args['demo'])
            self.client = Client(transport, cancelled=self.stop.is_set)
            self.emit('opened', demo=args['demo'], port=args['port'])
            self._status()  # Innocuous query verifies protocol/capabilities, not just open().
        elif action == 'disconnect':
            self._disconnect()
            self.emit('disconnected')
        elif self.client is None:
            raise OSError('puerto no abierto')
        elif action == 'status':
            self._status(args.get('capture_terminal', False))
        elif action == 'snapshot':
            self._snapshot()
        elif action == 'memory':
            self._memory(args['address'], args['count'])
            self._status()
        elif action == 'load':
            self.client.load(args['words'], args['entry'], args['preserve'],
                             lambda done, total: self.emit('progress', done=done, total=total))
            self.effect_acknowledged = True
            self.emit('loaded', words=args['words'], entry=args['entry'], preserve=args['preserve'],
                      confirmation='ACK BEGIN/DATA/COMMIT; sin lectura de IMEM')
            self._snapshot()
        elif action in ('step', 'pause', 'restart', 'run', 'limit'):
            payload = (bytes([args['preserve']]) if action == 'restart' else
                       struct.pack('<I', args['cycles']) if action == 'limit' else b'')
            self.client.request(action, payload)
            self.effect_acknowledged = True
            self.emit('ack', action=action)
            if action in ('step', 'pause', 'restart'):
                self._snapshot(include_used=action == 'step')
            else:
                # Only a terminal STATUS permits automatic capture after RUN.
                self._status(capture_terminal=action == 'run')
        else:
            raise ValueError(f'operación desconocida: {action}')

    def _loop(self):
        try:
            while not self.stop.is_set():
                try:
                    action, args = self.operations.get(timeout=0.1)
                except queue.Empty:
                    continue
                try:
                    self.effect_acknowledged = False
                    self._execute(action, args)
                except Exception as error:
                    # No retries. A later STATUS is always an explicit safe recovery.
                    uncertain = not self.effect_acknowledged and not isinstance(error, (ResponseError, ValueError))
                    self.emit('error', action=action, message=str(error),
                              uncertain=uncertain, effect_acknowledged=self.effect_acknowledged,
                              error_type=type(error).__name__)
                    if isinstance(error, OSError) and not isinstance(error, TimeoutError):
                        self._disconnect()
                        self.emit('disconnected')
                finally:
                    self.emit('done', action=action)
                    self.operations.task_done()
        finally:
            self._disconnect()
            self.emit('closed')
