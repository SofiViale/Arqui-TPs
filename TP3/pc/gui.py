#!/usr/bin/env python3
"""Interfaz de escritorio TP3. Ejecutar con --demo para usar datos simulados."""
import argparse
import json
import queue
import tkinter as tk
from datetime import datetime, timezone
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from model import Evidence, disassemble, now, read_program, validate_memory, validate_program
from snapshot import CAUSES, STATES, signed32
from worker import SerialWorker

ROOT = Path(__file__).resolve().parents[1]
MONO = ('Consolas', 10)
STAGE_COLORS = ('#2563eb', '#0f766e', '#7c3aed', '#c2410c', '#be185d')


def age(item):
    if not item:
        return 'sin lectura'
    elapsed = max(0, (datetime.now(timezone.utc) - datetime.fromisoformat(item['at'])).total_seconds())
    state = 'ANTERIOR: ' + item['stale_reason'] if item.get('stale_reason') else 'última lectura'
    return f"{item['at']} · hace {elapsed:.0f} s · {state}"


class DebugApp:
    def __init__(self, root, demo=False, program=None, worker=None):
        self.root, self.demo = root, demo
        self.worker = worker or SerialWorker()
        self.evidence = Evidence()
        self.opened = self.verified = self.busy = self.closing = False
        self.words = []
        self.previous_regs = None
        self.status_values = None
        self.stopped = False
        self.pipeline_empty = False
        self.pending = None
        self.after_ids = {}
        self.operation_failed = False
        self.awaiting_run_end = False
        self.port = tk.StringVar()
        self.connection = tk.StringVar(value='Desconectado')
        self.summary = tk.StringVar(value='Estado de CPU desconocido')
        self.status_age = tk.StringVar(value='STATUS: sin lectura')
        self.snapshot_age = tk.StringVar(value='SNAPSHOT: sin lectura')
        self.memory_age = tk.StringVar(value='DMEM: sin lectura')
        self.program_label = tk.StringVar(value='Ningún archivo local seleccionado')
        self.load_label = tk.StringVar(value='IMEM no es legible. Aún no se obtuvo COMMIT.')
        self.operation = tk.StringVar(value='Listo')
        self.entry = tk.StringVar(value='0')
        self.preserve = tk.BooleanVar(value=False)
        self.poll = tk.BooleanVar(value=True)
        self.address = tk.StringVar(value='0x0')
        self.count = tk.StringVar(value='16')
        self.limit = tk.StringVar(value='1000000')
        self.buttons = {}
        self._build()
        self.refresh_ports()
        if program:
            self.select_program(program)
        self.root.protocol('WM_DELETE_WINDOW', self.close)
        self.root.bind('<Destroy>', self._on_destroy, add='+')
        self.root.bind('<Configure>', self._resize, add='+')
        self._sync_actions()
        self._schedule('drain', 50, self._drain)
        self._schedule('poll', 1500, self._poll_status)
        self._schedule('ages', 500, self._ages)

    def _schedule(self, name, delay, callback):
        self.after_ids[name] = self.root.after(delay, callback)

    def _on_destroy(self, event):
        if event.widget is self.root:
            for identifier in self.after_ids.values():
                try:
                    self.root.after_cancel(identifier)
                except tk.TclError:
                    pass
            self.worker.close()

    def _resize(self, event):
        if event.widget is self.root:
            for label in self.wrapped_labels:
                label.configure(wraplength=max(500, event.width - 90))
            self.operation_label.configure(wraplength=max(450, event.width - 260))

    def _build(self):
        r = self.root
        r.title('TP3 · Laboratorio del procesador' + (' · DEMOSTRACIÓN' if self.demo else ''))
        r.geometry('1280x850')
        r.minsize(1000, 720)
        style = ttk.Style(r)
        style.theme_use('clam')
        style.configure('TFrame', background='#f1f5f9')
        style.configure('TLabel', background='#f1f5f9', foreground='#0f172a')
        style.configure('TLabelframe', background='#f1f5f9')
        style.configure('TLabelframe.Label', background='#f1f5f9', foreground='#334155')
        style.configure('TButton', padding=(10, 6))
        style.configure('Treeview', font=MONO, rowheight=25)
        style.configure('Treeview.Heading', font=('Segoe UI', 10, 'bold'))
        style.configure('Title.TLabel', font=('Segoe UI', 19, 'bold'))
        style.configure('Note.TLabel', foreground='#475569')
        r.columnconfigure(0, weight=1)
        r.rowconfigure(3, weight=1)

        header = ttk.Frame(r, padding=(18, 12))
        header.grid(row=0, column=0, sticky='ew')
        ttk.Label(header, text='TP3  /  Laboratorio del procesador', style='Title.TLabel').pack(side='left')
        tk.Label(header, text='MODO DEMOSTRACIÓN — SIN FPGA' if self.demo else 'BASYS 3 · UART REAL',
                 bg='#fef3c7' if self.demo else '#dbeafe', fg='#92400e' if self.demo else '#1e40af',
                 font=('Segoe UI', 11, 'bold'), padx=12, pady=8).pack(side='right')

        connect = ttk.Frame(r, padding=(18, 0, 18, 8))
        connect.grid(row=1, column=0, sticky='ew')
        ttk.Label(connect, text='Puerto').pack(side='left')
        self.ports = ttk.Combobox(connect, textvariable=self.port, width=18, state='readonly')
        self.ports.pack(side='left', padx=6)
        self.buttons['ports'] = ttk.Button(connect, text='Actualizar puertos', command=self.refresh_ports)
        self.buttons['ports'].pack(side='left')
        self.buttons['connect'] = ttk.Button(connect, text='Conectar', command=self.connect)
        self.buttons['connect'].pack(side='left', padx=6)
        self.buttons['disconnect'] = ttk.Button(connect, text='Desconectar', command=lambda: self.perform('disconnect'))
        self.buttons['disconnect'].pack(side='left')
        ttk.Label(connect, text='9600 baud · 8N1 · sin flow control', style='Note.TLabel').pack(side='left', padx=12)
        ttk.Label(connect, textvariable=self.connection, font=('Segoe UI', 10, 'bold')).pack(side='right')

        controls = ttk.Frame(r, padding=(18, 0, 18, 8))
        controls.grid(row=2, column=0, sticky='ew')
        controls.columnconfigure(0, weight=1)
        row = ttk.Frame(controls)
        row.grid(row=0, column=0, sticky='ew')
        for action, label in [('status', 'Consultar STATUS'), ('step', 'Avanzar un ciclo'),
                              ('run', 'Ejecutar RUN'), ('pause', 'Pausar y capturar'),
                              ('snapshot', 'Capturar (pausa CPU)'), ('restart', 'Reiniciar ejecución')]:
            self.buttons[action] = ttk.Button(row, text=label, command=lambda a=action: self.perform(a))
            self.buttons[action].pack(side='left', padx=(0, 6))
        ttk.Label(controls, textvariable=self.summary, font=('Segoe UI', 11, 'bold')).grid(row=1, column=0, sticky='w', pady=(8, 0))
        status_label = ttk.Label(controls, textvariable=self.status_age, style='Note.TLabel')
        status_label.grid(row=2, column=0, sticky='w')
        self.wrapped_labels = [status_label]
        ttk.Label(controls, text='Captura y DMEM dejan la CPU pausada. Desconectar o cerrar no detiene la CPU.',
                  style='Note.TLabel').grid(row=3, column=0, sticky='w')

        self.tabs = ttk.Notebook(r)
        self.tabs.grid(row=3, column=0, sticky='nsew', padx=18)
        pipeline, regs, program, memory, logs = [ttk.Frame(self.tabs, padding=12) for _ in range(5)]
        for frame, title in zip((pipeline, regs, program, memory, logs),
                                ('Pipeline', 'Registros x0–x31', 'Programa y carga', 'Memoria DMEM', 'Registro y exportación')):
            self.tabs.add(frame, text=title)

        pipeline.columnconfigure(0, weight=1)
        pipeline.rowconfigure(2, weight=1)
        ttk.Label(pipeline, textvariable=self.snapshot_age, style='Note.TLabel').grid(row=0, column=0, sticky='w')
        ttk.Label(pipeline, text='Color = etapa · valid=0: burbuja (payload sin efecto) · NOP válido: valid=1 y 00000013\n'
                  'Stall, flush y selección de forwarding: No disponible. Los operandos ID/EX son anteriores al forwarding.',
                  style='Note.TLabel').grid(row=1, column=0, sticky='w', pady=(6, 12))
        columns = ttk.Frame(pipeline)
        columns.grid(row=2, column=0, sticky='nsew')
        columns.rowconfigure(0, weight=1)
        self.stage_tables = []
        self.stage_labels = []
        for i, title in enumerate(('IF · búsqueda', 'ID · IF/ID', 'EX · ID/EX', 'MEM · EX/MEM', 'WB · MEM/WB')):
            columns.columnconfigure(i, weight=1, uniform='stage')
            panel = ttk.Frame(columns)
            panel.grid(row=0, column=i, sticky='nsew', padx=3)
            panel.columnconfigure(0, weight=1)
            panel.rowconfigure(2, weight=1)
            tk.Label(panel, text=title, bg=STAGE_COLORS[i], fg='white', font=('Segoe UI', 11, 'bold'), pady=9).grid(row=0, column=0, sticky='ew')
            label = ttk.Label(panel, text='Sin captura', wraplength=175)
            label.grid(row=1, column=0, sticky='ew', pady=8)
            table = self._table(panel, ('Campo', 'Valor'), (100, 100), row=2)
            self.stage_labels.append(label)
            self.stage_tables.append(table)
        self.capture_details = tk.StringVar(value='Capturar para ver cabecera y metadatos de excepción.')
        details_label = ttk.Label(pipeline, textvariable=self.capture_details, wraplength=1150, style='Note.TLabel')
        details_label.grid(row=3, column=0, sticky='w', pady=(10, 0))
        self.wrapped_labels.append(details_label)

        regs.columnconfigure(0, weight=1)
        regs.rowconfigure(2, weight=1)
        ttk.Label(regs, text='Banco completo · amarillo: cambió desde la captura anterior de esta sesión · rojo: anomalía x0',
                  style='Note.TLabel').grid(row=0, column=0, sticky='w')
        ttk.Label(regs, textvariable=self.snapshot_age, style='Note.TLabel').grid(row=1, column=0, sticky='w', pady=6)
        self.reg_table = self._table(regs, ('Registro', 'Hexadecimal', 'Decimal sin signo', 'Decimal con signo'), (130, 230, 230, 230), row=2)
        self.reg_table.tag_configure('changed', background='#fef3c7')
        self.reg_table.tag_configure('anomaly', background='#fecaca')

        program.columnconfigure(0, weight=1)
        program.rowconfigure(4, weight=1)
        local = ttk.Frame(program)
        local.grid(row=0, column=0, sticky='ew')
        self.buttons['file'] = ttk.Button(local, text='Abrir archivo ASM…', command=self.choose_program)
        self.buttons['file'].pack(side='left')
        ttk.Label(local, text='Entrada (bytes)').pack(side='left', padx=(15, 6))
        ttk.Entry(local, textvariable=self.entry, width=12).pack(side='left')
        self.buttons['load'] = ttk.Button(local, text='Cargar programa validado', command=self.load)
        self.buttons['load'].pack(side='left', padx=12)
        program_label = ttk.Label(program, textvariable=self.program_label, wraplength=1100)
        program_label.grid(row=1, column=0, sticky='w', pady=8)
        self.wrapped_labels.append(program_label)
        ttk.Checkbutton(program, text='Conservar DMEM en CARGA y REINICIO (desmarcado: limpiar DMEM)',
                        variable=self.preserve).grid(row=2, column=0, sticky='w')
        load_label = ttk.Label(program, textvariable=self.load_label, style='Note.TLabel', wraplength=1100)
        load_label.grid(row=3, column=0, sticky='w', pady=8)
        self.wrapped_labels.append(load_label)
        self.program_table = self._table(program, ('Dirección byte', 'Palabra local', 'Desensamblado del archivo local'), (160, 180, 650), row=4)
        self.program_table.tag_configure('pc', background='#dbeafe')
        ttk.Label(program, text='Azul: coincide con el último PC de fetch observado; no indica retiro ni verifica IMEM.\n'
                  'Para cargar: capturar con pipeline vacío; si está ocupado, reiniciar ejecución. Formato: ASM, máximo 256 palabras.', style='Note.TLabel').grid(row=5, column=0, sticky='w', pady=8)

        memory.columnconfigure(0, weight=1)
        memory.rowconfigure(3, weight=1)
        fields = ttk.Frame(memory)
        fields.grid(row=0, column=0, sticky='ew')
        for title, variable in [('Dirección byte', self.address), ('Cantidad bytes', self.count)]:
            ttk.Label(fields, text=title).pack(side='left', padx=(0, 6))
            ttk.Entry(fields, textvariable=variable, width=12).pack(side='left', padx=(0, 16))
        self.buttons['memory'] = ttk.Button(fields, text='Pausar y leer DMEM', command=self.read_memory)
        self.buttons['memory'].pack(side='left')
        ttk.Label(memory, text='Rango: 0..1023 bytes; dirección y cantidad múltiplos de 4. Sin escritura por UART.\n'
                  'Lectura a pedido, separada de SNAPSHOT; no se lee DMEM mediante polling.', style='Note.TLabel').grid(row=1, column=0, sticky='w', pady=8)
        ttk.Label(memory, textvariable=self.memory_age, style='Note.TLabel').grid(row=2, column=0, sticky='w', pady=6)
        self.memory_table = self._table(memory, ('Dirección byte', 'Bytes little-endian', 'Hexadecimal', 'Sin signo', 'Con signo'), (160, 220, 180, 180, 180), row=3)

        logs.columnconfigure(0, weight=1)
        logs.rowconfigure(2, weight=1)
        settings = ttk.Frame(logs)
        settings.grid(row=0, column=0, sticky='ew')
        ttk.Checkbutton(settings, text='STATUS cada 1,5 s; capturar al finalizar RUN', variable=self.poll).pack(side='left')
        ttk.Label(settings, text='Watchdog (ciclos; 0=sin límite)').pack(side='left', padx=8)
        ttk.Entry(settings, textvariable=self.limit, width=12).pack(side='left')
        self.buttons['limit'] = ttk.Button(settings, text='Aplicar límite', command=self.set_limit)
        self.buttons['limit'].pack(side='left', padx=8)
        ttk.Button(logs, text='Exportar lecturas y log a JSON…', command=self.export).grid(row=1, column=0, sticky='w', pady=10)
        logframe = ttk.Frame(logs)
        logframe.grid(row=2, column=0, sticky='nsew')
        logframe.columnconfigure(0, weight=1)
        logframe.rowconfigure(0, weight=1)
        self.log_widget = tk.Text(logframe, font=MONO, state='disabled', wrap='word', bg='#0f172a', fg='#e2e8f0')
        self.log_widget.grid(row=0, column=0, sticky='nsew')
        scroll = ttk.Scrollbar(logframe, command=self.log_widget.yview)
        scroll.grid(row=0, column=1, sticky='ns')
        self.log_widget.configure(yscrollcommand=scroll.set)

        footer = ttk.Frame(r, padding=(18, 10))
        footer.grid(row=4, column=0, sticky='ew')
        footer.columnconfigure(0, weight=1)
        self.operation_label = ttk.Label(footer, textvariable=self.operation, wraplength=950)
        self.operation_label.grid(row=0, column=0, sticky='w')
        self.progress = ttk.Progressbar(footer, length=180, maximum=100)
        self.progress.grid(row=0, column=1)
        self.record('Interfaz iniciada. ' + ('Datos simulados; RUN a 40 ciclos/s; no certifica FPGA.' if self.demo else 'UART real; seleccionar el puerto de la Basys 3.'))

    def _table(self, parent, columns, widths, row):
        frame = ttk.Frame(parent)
        frame.grid(row=row, column=0, sticky='nsew')
        frame.rowconfigure(0, weight=1)
        frame.columnconfigure(0, weight=1)
        tree = ttk.Treeview(frame, columns=columns, show='headings', height=12)
        for column, width in zip(columns, widths):
            tree.heading(column, text=column)
            tree.column(column, width=width, minwidth=80, stretch=True)
        tree.grid(row=0, column=0, sticky='nsew')
        y = ttk.Scrollbar(frame, orient='vertical', command=tree.yview)
        y.grid(row=0, column=1, sticky='ns')
        x = ttk.Scrollbar(frame, orient='horizontal', command=tree.xview)
        x.grid(row=1, column=0, sticky='ew')
        tree.configure(yscrollcommand=y.set, xscrollcommand=x.set)
        return tree

    def record(self, message):
        self.evidence.record(message)
        self.log_widget.configure(state='normal')
        self.log_widget.insert('end', f"{self.evidence.log[-1]['at']}  {message}\n")
        self.log_widget.see('end')
        self.log_widget.configure(state='disabled')

    def refresh_ports(self):
        try:
            if self.demo:
                ports = ['SIMULADO']
            else:
                from serial.tools.list_ports import comports
                found = list(comports())
                ports = [p.device for p in found]
                self.record('Puertos: ' + (', '.join(f'{p.device}: {p.description}' for p in found) or 'ninguno'))
            self.ports['values'] = ports
            if self.port.get() not in ports:
                self.port.set(ports[0] if ports else '')
        except (ImportError, OSError) as error:
            self.record(f'No se pudieron enumerar puertos: {error}. Instalar requirements.txt.')

    def connect(self):
        if not self.demo and not self.port.get():
            self._validation_error(ValueError('seleccionar un puerto serie'))
            return
        self.evidence.new_session('simulado' if self.demo else 'UART real')
        self.previous_regs = None
        self.status_values = None
        self.stopped = self.pipeline_empty = False
        self._clear_observations()
        self.perform('connect', port=self.port.get(), demo=self.demo)

    def _clear_observations(self):
        for table in (self.reg_table, self.memory_table, *self.stage_tables):
            table.delete(*table.get_children())
        for label in self.stage_labels:
            label.configure(text='Sin captura de esta sesión')
        self.capture_details.set('Sin captura de esta sesión.')
        self.load_label.set('IMEM no es legible. Sin confirmación de carga en esta sesión.')
        self.summary.set('Estado de CPU desconocido')
        self._program_rows()

    def perform(self, action, **arguments):
        if self.busy or self.closing:
            return
        if action == 'restart':
            arguments['preserve'] = self.preserve.get()
        if action == 'status':
            arguments.setdefault('capture_terminal', self.awaiting_run_end)
        self.busy, self.pending = True, action
        self.operation_failed = False
        if action == 'run':
            self.awaiting_run_end = True
        elif action not in ('status', 'connect'):
            self.awaiting_run_end = False
        if action not in ('connect', 'status', 'disconnect'):
            self.evidence.invalidate(f'operación {action} solicitada; volver a leer')
            self.stopped = self.pipeline_empty = False
        self.operation.set(f'Pendiente: {action}…')
        self.record(f'Solicitud {action}' + ('; limpiar DMEM' if action in ('load', 'restart') and not arguments.get('preserve') else ''))
        self.worker.submit(action, **arguments)
        self._sync_actions()

    def choose_program(self):
        path = filedialog.askopenfilename(parent=self.root, title='Seleccionar programa ASM', initialdir=ROOT / 'programs',
                                          filetypes=[('Ensamblador TP3', '*.asm'), ('Archivos de texto', '*.txt'), ('Todos', '*.*')])
        if path:
            self.select_program(path)

    def select_program(self, path):
        try:
            entry = int(self.entry.get(), 0)
            words = read_program(path, entry)
        except (ValueError, OSError) as error:
            self._validation_error(error)
            return
        self.words = words
        self.evidence.local_program = dict(path=str(Path(path).resolve()), at=now(), words=words,
                                           entry=entry, provenance='archivo local; no leído de IMEM')
        self.program_label.set(f'LOCAL · {path} · {len(words)} palabras / {len(words) * 4} bytes · validado')
        self.record(f'Archivo ASM validado: {path} ({len(words) * 4} bytes); sin transmitir.')
        self._program_rows()
        self._sync_actions()

    def load(self):
        try:
            entry = int(self.entry.get(), 0)
            validate_program(self.words, entry)
        except ValueError as error:
            self._validation_error(error)
            return
        self.progress['value'] = 0
        self.load_label.set('Carga solicitada; esperando ACK de BEGIN/DATA/COMMIT. IMEM sin lectura de verificación.')
        self.perform('load', words=list(self.words), entry=entry, preserve=self.preserve.get())

    def read_memory(self):
        try:
            address, count = int(self.address.get(), 0), int(self.count.get(), 0)
            validate_memory(address, count)
        except ValueError as error:
            self._validation_error(error)
            return
        self.perform('memory', address=address, count=count)

    def set_limit(self):
        try:
            cycles = int(self.limit.get(), 0)
            if not 0 <= cycles <= 0xffffffff:
                raise ValueError('límite fuera de uint32')
        except ValueError as error:
            self._validation_error(error)
            return
        self.perform('limit', cycles=cycles)

    def _validation_error(self, error):
        self.operation.set(f'Validación: {error}')
        self.record(f'Validación rechazada: {error}')
        messagebox.showerror('Datos inválidos', str(error), parent=self.root)

    def _drain(self):
        while True:
            try:
                event = self.worker.events.get_nowait()
            except queue.Empty:
                break
            self.handle_event(event)
        self._sync_actions()
        if self.closing and not self.worker.thread.is_alive():
            self.root.destroy()
            return
        self._schedule('drain', 50, self._drain)

    def handle_event(self, event):
        kind = event['kind']
        at = event['at']
        if kind == 'opened':
            self.opened, self.verified = True, False
            self.connection.set('Puerto abierto · sin verificar')
            self.record('Puerto abierto; verificando STATUS/schema.')
        elif kind == 'status':
            values = event['values']
            self.status_values = values
            self.verified = True
            self.connection.set('SIMULADO · verificado' if self.demo else f'{self.port.get()} · comunicación verificada')
            state, cause, valid = values[8] & 7, (values[8] >> 8) & 255, bool(values[8] & 8)
            self.evidence.status = dict(at=at, values=values, source=self.evidence.source,
                                       coherence='flags/PC/ciclos capturados juntos por STATUS')
            capture = self.evidence.capture
            if capture:
                h = capture['decoded']['header']
                if (h[1], h[2], h[3], h[15]) != (state, values[9], values[10], int(valid)):
                    capture['stale_reason'] = 'STATUS posterior difiere de la captura'
                    if self.evidence.memory:
                        self.evidence.memory['stale_reason'] = 'estado posterior; volver a leer DMEM'
            # STATUS has no running bit for state=2; do not infer paused draining.
            self.stopped = state in (0, 3, 4) or bool(capture and not capture.get('stale_reason') and not capture['decoded']['header'][14])
            self.pipeline_empty = bool(capture and not capture.get('stale_reason') and capture['decoded']['header'][6] == 0)
            self.summary.set(f'{STATES[state].upper()} · causa: {CAUSES[cause]} · PC fetch 0x{values[9]:08x} · '
                             f'{values[10]} ciclos · programa {"válido" if valid else "inválido"}' +
                             (' · running no disponible en STATUS' if state == 2 else ''))
            self._program_rows()
        elif kind == 'snapshot':
            decoded = event['decoded']
            self.evidence.capture = dict(at=at, raw_hex=event['raw'], decoded=decoded, source=self.evidence.source,
                                         coherence='256 bytes de una captura coherente; CPU pausada')
            self._render_snapshot(decoded)
            h = decoded['header']
            self.stopped, self.pipeline_empty = not h[14], h[6] == 0
            # Do not manufacture a STATUS observation from a snapshot.
            self.status_values = (h[0], 1024, 512, 128, 64, 196, 141, 103, h[1] | h[15] << 3 | h[4] << 8, h[2], h[3])
            self.summary.set(f'{STATES[h[1]].upper()} · causa: {CAUSES[h[4]]} · PC fetch 0x{h[2]:08x} · '
                             f'{h[3]} ciclos · running={h[14]} · programa {"válido" if h[15] else "inválido"}')
            self.record('SNAPSHOT recibido: registros/pipeline coherentes; CPU pausada.')
            self._program_rows()
        elif kind == 'memory':
            self.evidence.memory = dict(at=at, address=event['address'], raw_hex=event['raw'],
                                       source=self.evidence.source, coherence=event['coherence'])
            self.memory_table.delete(*self.memory_table.get_children())
            raw = bytes.fromhex(event['raw'])
            for offset in range(0, len(raw), 4):
                chunk = raw[offset:offset + 4]
                v = int.from_bytes(chunk, 'little')
                self.memory_table.insert('', 'end', values=(f'0x{event["address"] + offset:08x}', chunk.hex(' '), f'0x{v:08x}', v, signed32(v)))
            self.record(f'DMEM: {len(raw)} bytes recibidos; lectura separada del snapshot.')
        elif kind == 'progress':
            self.progress['value'] = 100 * event['done'] / event['total']
            self.operation.set(f'DATA confirmado: {event["done"]}/{event["total"]} bytes; falta COMMIT/captura')
        elif kind == 'loaded':
            self.evidence.load_ack = dict(at=at, source=self.evidence.source, **{k: event[k] for k in ('words', 'entry', 'preserve', 'confirmation')})
            self.load_label.set(f'COMMIT confirmado · {len(event["words"]) * 4} bytes · sin lectura de IMEM · {at}')
            self.record('Carga confirmada por ACK de COMMIT. No hay verificación por lectura de IMEM.')
        elif kind == 'ack':
            self.record(f'ACK recibido: {event["action"]}; solicitando lectura posterior.')
        elif kind == 'close_warning':
            self.record(event['message'])
        elif kind == 'error':
            self.operation_failed = True
            self.awaiting_run_end = False
            self.verified = False
            self.stopped = self.pipeline_empty = False
            self.evidence.invalidate('fallo de comunicación; recuperar con STATUS/captura')
            message = f'{event["error_type"]}: {event["message"]}'
            if event['error_type'] in ('SerialException', 'OSError'):
                message = 'Fallo del puerto serie: comprobar USB, puerto ocupado y reconectar. ' + message
            if event['uncertain']:
                message += ' Resultado de la operación incierto; no repetir automáticamente. Consultar STATUS.'
            if event.get('effect_acknowledged'):
                message += ' El comando con efectos ya recibió ACK; falló la lectura posterior. Consultar STATUS sin repetirlo.'
            if event['action'] == 'load':
                if event.get('effect_acknowledged'):
                    self.load_label.set('COMMIT confirmado; falló la captura posterior. IMEM sin lectura de verificación. Consultar STATUS.')
                else:
                    self.load_label.set('Carga interrumpida o confirmación incompleta. Consultar STATUS; no asumir programa válido.')
            self.operation.set(message)
            self.connection.set('Puerto abierto · comunicación sin verificar' if self.opened else 'Sin conexión')
            self.record('ERROR: ' + message)
        elif kind == 'disconnected':
            self.opened = self.verified = self.stopped = self.pipeline_empty = False
            self.status_values = None
            self.evidence.invalidate('desconectado; datos históricos')
            self.connection.set('Desconectado · CPU puede seguir ejecutando')
            self.summary.set('CPU sin conexión; estado actual desconocido')
            self.record('Puerto cerrado. Desconectar no envía PAUSE.')
        elif kind == 'done':
            self.busy, self.pending = False, None
            # Preserve errors; done means queue completion, not command success.
            if not self.operation_failed:
                self.operation.set(f'Operación {event["action"]} completada; revisar lecturas y log.')

    def _render_snapshot(self, decoded):
        h, registers = decoded['header'], decoded['registers']
        self.reg_table.delete(*self.reg_table.get_children())
        for i, v in enumerate(registers):
            tags = ('anomaly',) if i == 0 and v != 0 else ('changed',) if self.previous_regs is not None and self.previous_regs[i] != v else ()
            self.reg_table.insert('', 'end', values=(f'x{i}', f'0x{v:08x}', v, signed32(v)), tags=tags)
        if registers[0]:
            self.record(f'ANOMALÍA: x0 recibido = 0x{registers[0]:08x}; no se ocultó el valor.')
        self.previous_regs = tuple(registers)
        for table in self.stage_tables:
            table.delete(*table.get_children())
        self.stage_labels[0].configure(text=f'PC fetch = 0x{h[2]:08x}\nInstrucción/valid: No disponible')
        for key, value in [('PC fetch', f'0x{h[2]:08x}'), ('instrucción', 'No disponible'), ('valid', 'No disponible')]:
            self.stage_tables[0].insert('', 'end', values=(key, value))
        for i, stage in enumerate(decoded['pipeline']):
            valid = (h[6] >> i) & 1
            self.stage_labels[i + 1].configure(text=f'valid={valid} · {"válida" if valid else "burbuja"}\n' + disassemble(stage['instruction']))
            for key, value in stage.items():
                self.stage_tables[i + 1].insert('', 'end', values=(key, f'0x{value:08x}' if key in ('pc', 'instruction', 'operand1', 'operand2', 'immediate', 'result', 'store_data', 'write_data') else str(value)))
        used = f'bytes {h[9]}..{h[10]} inclusive' if h[8] else 'sin accesos'
        self.capture_details.set(f'PC de parada/error=0x{h[5]:08x} · excepción FI.fetch={h[7] & 1}, IX.fetch={(h[7] >> 1) & 1}, IX.illegal={(h[7] >> 2) & 1}\n'
                                 f'DMEM usada: {used} · programa={h[11]} bytes · entrada={h[12]} · watchdog={h[13]} ciclos · running={h[14]} · programa válido={h[15]}')

    def _program_rows(self):
        self.program_table.delete(*self.program_table.get_children())
        pc = self.status_values[9] if self.status_values else None
        for i, word in enumerate(self.words):
            self.program_table.insert('', 'end', values=(f'0x{i * 4:08x}', f'0x{word:08x}', disassemble(word)),
                                      tags=('pc',) if pc == i * 4 else ())

    def _sync_actions(self):
        free = not self.busy and not self.closing
        live = free and self.verified
        state = (self.status_values[8] & 7) if self.status_values else None
        valid = bool(self.status_values and self.status_values[8] & 8)
        allowed = dict(connect=free and not self.opened, disconnect=free and self.opened,
                       ports=free and not self.opened, file=free,
                       status=free and self.opened, snapshot=live, memory=live, pause=live,
                       restart=live, run=live and valid and self.stopped and state not in (3, 4),
                       step=live and valid and self.stopped and state not in (3, 4),
                       load=live and self.stopped and self.pipeline_empty and bool(self.words),
                       limit=live and self.stopped)
        for name, button in self.buttons.items():
            button.configure(state='normal' if allowed[name] else 'disabled')
        self.ports.configure(state='readonly' if free and not self.opened else 'disabled')

    def _poll_status(self):
        if self.closing:
            return
        if self.poll.get() and self.verified and not self.busy and self.status_values and self.status_values[8] & 7 in (1, 2):
            self.perform('status', capture_terminal=self.awaiting_run_end)
        self._schedule('poll', 1500, self._poll_status)

    def _ages(self):
        self.status_age.set('STATUS: ' + age(self.evidence.status))
        self.snapshot_age.set('SNAPSHOT: ' + age(self.evidence.capture))
        self.memory_age.set('DMEM: ' + age(self.evidence.memory))
        if not self.closing:
            self._schedule('ages', 500, self._ages)

    def export(self, path=None):
        if path is None:
            path = filedialog.asksaveasfilename(parent=self.root, title='Exportar evidencia observada',
                                               defaultextension='.json', initialfile='tp3_evidencia.json',
                                               filetypes=[('JSON', '*.json')])
        if not path:
            return
        try:
            self.record(f'Exportación JSON: {path}')
            data = self.evidence.export()
            data['connection'] = dict(port=self.port.get(), opened=self.opened, verified=self.verified,
                                      pending_operation=self.pending, baud=9600, framing='8N1; sin flow control')
            Path(path).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
            self.operation.set(f'Evidencia exportada: {path}')
        except OSError as error:
            self._validation_error(error)

    def close(self):
        if self.closing:
            return
        self.closing = True
        self.evidence.invalidate('cierre solicitado; una operación pendiente puede haberse ejecutado')
        self.operation.set('Cerrando el puerto en el hilo UART… La CPU no recibe PAUSE al cerrar.')
        self.record('Cierre solicitado; no se envían comandos adicionales ni reintentos.')
        self.worker.close()
        self._sync_actions()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--demo', action='store_true', help='modo explícito sin FPGA')
    parser.add_argument('--program', type=Path, help='ASM local para previsualizar; no se carga automáticamente')
    args = parser.parse_args(argv)
    root = tk.Tk()
    DebugApp(root, demo=args.demo, program=args.program)
    root.mainloop()


if __name__ == '__main__':
    main()
