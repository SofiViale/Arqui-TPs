#!/usr/bin/env python3
"""Calculator UI for the FPGA ALU. Run: python TP2/pc/calculator.py"""

import queue
import sys

try:
    from PySide6.QtCore import QEvent, QRegularExpression, QThread, Qt, Signal
    from PySide6.QtGui import QFont, QRegularExpressionValidator
    from PySide6.QtWidgets import (
        QApplication, QComboBox, QFrame, QGridLayout, QHBoxLayout,
        QLabel, QLineEdit, QMainWindow, QPlainTextEdit, QPushButton, QScrollArea,
        QSizePolicy, QVBoxLayout, QWidget,
    )
    from serial.tools import list_ports
    from serial_client import AluConnection, CommunicationError
except ImportError as error:
    raise SystemExit(
        f"Falta una dependencia: {error}\n"
        "Ejecutá: python -m pip install -r TP2/pc/requirements.txt"
    ) from error

from protocol import DESCRIPTIONS, OPERATIONS, Request, parse_operand, signed_byte


class SerialWorker(QThread):
    """One thread owns the port. Qt signals deliver results to the UI thread."""

    opened = Signal(str)
    disconnected = Signal()
    received = Signal(object, int)
    failed = Signal(str)
    ports_found = Signal(object)

    def __init__(self, connection=None, parent=None):
        super().__init__(parent)
        self.commands = queue.Queue()
        self.connection = connection if connection is not None else AluConnection()

    def submit(self, command, value=None):
        self.commands.put((command, value))

    def run(self):
        try:
            while True:
                command, value = self.commands.get()
                if command == "quit":
                    return
                try:
                    if command == "ports":
                        self.ports_found.emit([
                            (port.device, port.description) for port in list_ports.comports()
                        ])
                    elif command == "connect":
                        self.connection.connect(value)
                        self.opened.emit(value)
                    elif command == "disconnect":
                        self.connection.close()
                        self.disconnected.emit()
                    elif command == "exchange":
                        result = self.connection.exchange(value)
                        self.received.emit(value, result)
                except (CommunicationError, OSError) as error:
                    self.connection.close()
                    self.failed.emit(str(error))
        finally:
            self.connection.close()


STYLE = """
QWidget { background: #101820; color: #ecf2f8; font-family: 'Segoe UI'; font-size: 14px; }
QFrame#card { background: #192630; border: 1px solid #30404c; border-radius: 12px; }
QFrame#card QLabel { background: transparent; border: none; }
QLabel#eyebrow { color: #72ddbf; font-weight: 700; letter-spacing: 2px; }
QLabel#title { font-size: 30px; font-weight: 700; }
QLabel#muted { color: #a6b8c8; }
QLabel#result { color: #72ddbf; font-size: 50px; font-weight: 700; }
QLabel#error { color: #ffad9e; }
QLineEdit, QComboBox, QPlainTextEdit {
    background: #0f1c26; border: 1px solid #3b5061; border-radius: 7px; padding: 8px;
    selection-background-color: #327563;
}
QLineEdit { font-size: 27px; font-weight: 600; }
QComboBox QLineEdit { font-size: 14px; font-weight: 400; }
QLineEdit:focus { border: 2px solid #72ddbf; }
QLineEdit[invalid="true"] { border: 2px solid #ffad9e; }
QPushButton {
    background: #263746; border: 1px solid #3b5061; border-radius: 8px;
    padding: 9px 13px; font-weight: 600;
}
QPushButton:hover { background: #354e60; }
QPushButton:pressed { background: #476478; }
QPushButton#operation { background: #194b43; color: #b7f8e5; font-size: 17px; }
QPushButton#operation:hover { background: #266b5c; }
QPushButton#number { font-size: 22px; }
QPushButton#connect { background: #72ddbf; color: #102820; }
QPushButton:disabled { background: #1b2630; color: #647686; border-color: #293947; }
QComboBox:disabled, QLineEdit:disabled { color: #8496a5; }
QPlainTextEdit { font-family: Consolas; font-size: 12px; }
"""


class CalculatorWindow(QMainWindow):
    def __init__(self, worker=None):
        super().__init__()
        self.worker = worker if worker is not None else SerialWorker(parent=self)
        self.connected = False
        self.busy = False
        self.active_operand = 0
        self.closing = False
        self.inputs = []
        self.previews = []
        self.key_buttons = []
        self.operation_buttons = {}
        self.setWindowTitle("Calculadora ALU · Arquitectura de Computadoras")
        self.resize(830, 880)
        self.setMinimumSize(700, 580)
        self.setStyleSheet(STYLE)
        self._build_ui()
        self.worker.opened.connect(self._opened)
        self.worker.disconnected.connect(self._disconnected)
        self.worker.received.connect(self._received)
        self.worker.failed.connect(self._failed)
        self.worker.ports_found.connect(self._ports_found)
        self.worker.finished.connect(self._worker_finished)
        self.worker.start()
        self.refresh_ports()
        self._update_inputs()
        self.inputs[0].setFocus()
        self.inputs[0].selectAll()

    @staticmethod
    def label(text, name=None):
        label = QLabel(text)
        if name:
            label.setObjectName(name)
        return label

    def _build_ui(self):
        central = QWidget()
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        scroll.setWidget(central)
        self.setCentralWidget(scroll)
        layout = QVBoxLayout(central)
        layout.setContentsMargins(26, 20, 26, 20)
        layout.setSpacing(12)
        layout.addWidget(self.label("ARQUITECTURA DE COMPUTADORAS  /  TP2", "eyebrow"))
        layout.addWidget(self.label("Calculadora ALU", "title"))
        layout.addWidget(self.label("Elegí A y B. Pulsá una operación para calcular en la FPGA.", "muted"))

        connection = QHBoxLayout()
        self.port_combo = QComboBox()
        self.port_combo.setEditable(True)
        self.port_combo.setMinimumWidth(180)
        self.port_combo.lineEdit().setPlaceholderText("Puerto, por ejemplo COM3")
        self.refresh_button = QPushButton("Actualizar")
        self.refresh_button.clicked.connect(self.refresh_ports)
        self.connect_button = QPushButton("Conectar")
        self.connect_button.setObjectName("connect")
        self.connect_button.clicked.connect(self.toggle_connection)
        connection.addWidget(self.port_combo, 1)
        connection.addWidget(self.refresh_button)
        connection.addWidget(self.connect_button)
        connection.addWidget(self.label("9600 baud · 8N1", "muted"))
        layout.addLayout(connection)
        self.status_label = self.label("Puerto desconectado. Podés preparar los operandos.", "muted")
        self.status_label.setWordWrap(True)
        layout.addWidget(self.status_label)

        operands = QHBoxLayout()
        for index, name in enumerate(("A", "B")):
            card = QFrame()
            card.setObjectName("card")
            contents = QVBoxLayout(card)
            contents.addWidget(self.label(f"OPERANDO {name}  ·  decimal 0–255", "muted"))
            field = QLineEdit("0")
            field.setAccessibleName(f"Operando {name}")
            field.setValidator(QRegularExpressionValidator(QRegularExpression("[0-9]*"), field))
            # Values >255 remain visible and invalid; never turn 256 into 25/0.
            field.installEventFilter(self)
            field.textChanged.connect(self._update_inputs)
            contents.addWidget(field)
            preview = self.label("00000000  ·  0x00", "muted")
            contents.addWidget(preview)
            self.inputs.append(field)
            self.previews.append(preview)
            operands.addWidget(card)
        layout.addLayout(operands)
        self.validation_label = self.label("", "error")
        self.validation_label.setMinimumHeight(20)
        layout.addWidget(self.validation_label)

        result_card = QFrame()
        result_card.setObjectName("card")
        result_layout = QVBoxLayout(result_card)
        self.expression_label = self.label("RESULTADO RECIBIDO DE LA FPGA", "muted")
        self.result_label = self.label("—", "result")
        self.result_label.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        self.result_details = self.label("Binario: —     Hex: —     Con signo: —", "muted")
        result_layout.addWidget(self.expression_label)
        result_layout.addWidget(self.result_label)
        result_layout.addWidget(self.result_details)
        layout.addWidget(result_card)

        controls = QHBoxLayout()
        self.active_label = self.label("Teclado → A", "eyebrow")
        controls.addWidget(self.active_label)
        controls.addStretch()
        self.switch_button = QPushButton("Editar B")
        self.switch_button.clicked.connect(self.switch_operand)
        self.swap_button = QPushButton("Intercambiar A / B")
        self.swap_button.clicked.connect(self.swap_operands)
        controls.addWidget(self.switch_button)
        controls.addWidget(self.swap_button)
        layout.addLayout(controls)

        keys = QHBoxLayout()
        numbers = QGridLayout()
        numbers.setSpacing(8)
        for index, text in enumerate(("7", "8", "9", "4", "5", "6", "1", "2", "3", "C", "0", "DEL")):
            button = QPushButton(text)
            button.setObjectName("number")
            button.setMinimumHeight(48)
            button.setFocusPolicy(Qt.FocusPolicy.NoFocus)
            button.clicked.connect(lambda checked=False, key=text: self.keypress(key))
            button.setToolTip("Limpiar el operando activo" if text == "C" else
                              "Borrar un dígito" if text == "DEL" else text)
            numbers.addWidget(button, index // 3, index % 3)
            self.key_buttons.append(button)
        operations = QGridLayout()
        operations.setSpacing(8)
        for index, name in enumerate(OPERATIONS):
            button = QPushButton(name)
            button.setObjectName("operation")
            button.setMinimumHeight(48)
            button.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)
            button.setToolTip(DESCRIPTIONS[name])
            button.clicked.connect(lambda checked=False, operation=name: self.calculate(operation))
            operations.addWidget(button, index // 2, index % 2)
            self.operation_buttons[name] = button
        keys.addLayout(numbers, 3)
        keys.addSpacing(12)
        keys.addLayout(operations, 2)
        layout.addLayout(keys)
        hint = self.label("SRA conserva el signo de A; SRL completa con ceros. B indica cuántas posiciones desplazar.", "muted")
        hint.setWordWrap(True)
        layout.addWidget(hint)

        layout.addWidget(self.label("ÚLTIMAS OPERACIONES", "muted"))
        self.history = QPlainTextEdit()
        self.history.setReadOnly(True)
        self.history.setMaximumBlockCount(50)
        self.history.setMaximumHeight(100)
        self.history.setPlaceholderText("Las respuestas de la placa aparecerán acá.")
        layout.addWidget(self.history)

    def eventFilter(self, watched, event):
        if event.type() == QEvent.Type.FocusIn and watched in self.inputs:
            self.active_operand = self.inputs.index(watched)
            self._update_active_label()
        return super().eventFilter(watched, event)

    def _update_active_label(self):
        self.active_label.setText(f"Teclado → {'AB'[self.active_operand]}")
        self.switch_button.setText(f"Editar {'BA'[self.active_operand]}")

    def switch_operand(self):
        self.active_operand = 1 - self.active_operand
        self._update_active_label()
        self.inputs[self.active_operand].setFocus()
        self.inputs[self.active_operand].selectAll()

    def swap_operands(self):
        a, b = (field.text() for field in self.inputs)
        self.inputs[0].setText(b)
        self.inputs[1].setText(a)

    def keypress(self, key):
        if self.busy:
            return
        field = self.inputs[self.active_operand]
        if key == "C":
            field.setText("0")
            field.selectAll()
        elif key == "DEL":
            field.backspace()
        else:
            if field.text() == "0":
                field.selectAll()
            field.insert(key)
        field.setFocus()

    def _update_inputs(self):
        errors = []
        for index, field in enumerate(self.inputs):
            try:
                value = parse_operand(field.text())
                self.previews[index].setText(f"{value:08b}  ·  0x{value:02X}")
                invalid = False
            except ValueError as error:
                invalid = True
                errors.append(f"{'AB'[index]}: {error}")
                self.previews[index].setText("Fuera de rango" if field.text() else "Ingresá un valor")
            field.setProperty("invalid", invalid)
            field.style().unpolish(field)
            field.style().polish(field)
        self.validation_label.setText(errors[0] if errors else "")
        for button in self.operation_buttons.values():
            button.setEnabled(self.connected and not self.busy and not errors)

    def _set_busy(self, busy):
        self.busy = busy
        self.connect_button.setEnabled(not busy)
        self.port_combo.setEnabled(not busy and not self.connected)
        self.refresh_button.setEnabled(not busy and not self.connected)
        for widget in [*self.inputs, *self.key_buttons, self.switch_button, self.swap_button]:
            widget.setEnabled(not busy)
        self._update_inputs()

    def refresh_ports(self):
        self.refresh_button.setEnabled(False)
        self.worker.submit("ports")

    def _ports_found(self, ports):
        previous = self.port_combo.currentText()
        self.port_combo.clear()
        for device, description in ports:
            self.port_combo.addItem(device)
            self.port_combo.setItemData(self.port_combo.count() - 1, description, Qt.ItemDataRole.ToolTipRole)
        if previous:
            self.port_combo.setEditText(previous)
        self.refresh_button.setEnabled(not self.busy and not self.connected)

    def toggle_connection(self):
        if self.busy:
            return
        port = self.port_combo.currentText().strip()
        if not self.connected and not port:
            self.status_label.setText("Seleccioná un puerto o escribí su nombre, por ejemplo COM3.")
            return
        self._set_busy(True)
        self.status_label.setText("Cerrando puerto…" if self.connected else f"Abriendo {port}…")
        self.worker.submit("disconnect" if self.connected else "connect", port)

    def _opened(self, port):
        self.connected = True
        self.connect_button.setText("Desconectar")
        self.status_label.setText(f"Puerto {port} abierto · 9600 baud. Elegí una operación.")
        self._set_busy(False)

    def _disconnected(self):
        self.connected = False
        self.connect_button.setText("Conectar")
        self.status_label.setText("Puerto desconectado.")
        self._set_busy(False)

    def calculate(self, operation):
        if not self.connected or self.busy:
            return
        try:
            request = Request(*(parse_operand(field.text()) for field in self.inputs), operation)
        except ValueError as error:
            self.validation_label.setText(str(error))
            return
        self._set_busy(True)
        self.expression_label.setText(f"{request.expression}  ·  esperando respuesta")
        self.result_label.setText("…")
        self.result_details.setText("Binario: —     Hex: —     Con signo: —")
        self.status_label.setText("Operación enviada. Esperando a la FPGA…")
        self.worker.submit("exchange", request)

    def _received(self, request, result):
        self.expression_label.setText(f"{request.expression}  ·  resultado recibido (sin signo)")
        self.result_label.setText(str(result))
        self.result_details.setText(f"Binario: {result:08b}     Hex: 0x{result:02X}     Con signo: {signed_byte(result)}")
        self.history.appendPlainText(
            f"{request.expression} = {result}   |   {result:08b}   |   0x{result:02X}"
        )
        self.status_label.setText("Respuesta recibida. Podés enviar otra operación.")
        self._set_busy(False)

    def _failed(self, message):
        self.connected = False
        self.connect_button.setText("Conectar")
        self.result_label.setText("—")
        self.result_details.setText("Binario: —     Hex: —     Con signo: —")
        self.expression_label.setText("OPERACIÓN SIN RESULTADO")
        self.status_label.setText(message)
        self._set_busy(False)

    def closeEvent(self, event):
        # Keep the Qt object alive until the bounded serial read/write finishes.
        # Closing never terminates a running QThread or touches its port from UI.
        if self.worker.isRunning():
            if not self.closing:
                self.closing = True
                self.centralWidget().setEnabled(False)
                self.status_label.setText("Cerrando conexión…")
                self.worker.submit("quit")
            event.ignore()
        else:
            event.accept()

    def _worker_finished(self):
        if self.closing:
            self.close()


def main():
    app = QApplication(sys.argv)
    app.setFont(QFont("Segoe UI", 10))
    window = CalculatorWindow()
    window.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
