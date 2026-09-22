"""Protocol, serial fault and offscreen GUI tests. No FPGA required."""

import os
from pathlib import Path
import re
import sys
import threading
import time
import unittest
from unittest.mock import Mock

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import serial
from PySide6.QtCore import Qt
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication

from calculator import CalculatorWindow, SerialWorker
from protocol import OPERATIONS, Request, parse_operand, signed_byte
from serial_client import AluConnection, CommunicationError


class FakePort:
    def __init__(self, response=b"\x0f"):
        self.is_open = True
        self.in_waiting = 0
        self.response = response
        self.writes = []
        self.read_sizes = []
        self.short_write = False
        self.write_error = None
        self.read_error = None
        self.gate = None

    def reset_input_buffer(self):
        self.in_waiting = 0

    def write(self, packet):
        if self.write_error:
            raise self.write_error
        self.writes.append(packet)
        return 2 if self.short_write else len(packet)

    def read(self, size):
        self.read_sizes.append(size)
        if self.gate is not None:
            self.gate.wait(1)
        if self.read_error:
            raise self.read_error
        return self.response

    def close(self):
        self.is_open = False


class ProtocolTests(unittest.TestCase):
    def test_decimal_boundaries_and_leading_zeros(self):
        for text, expected in (("0", 0), ("255", 255), (" 205 ", 205), ("000005", 5)):
            with self.subTest(text=text):
                self.assertEqual(parse_operand(text), expected)

    def test_rejects_overflow_negative_fraction_and_non_decimal_input(self):
        for text in ("", " ", "256", "999", "9" * 5000, "-1", "1.5", "0xFF", "12a", "１２", "+1"):
            with self.subTest(text=text[:20]):
                with self.assertRaises(ValueError):
                    parse_operand(text)

    def test_eight_exact_opcodes_and_packet_order(self):
        for name, code in (("ADD", 0x20), ("SUB", 0x22), ("AND", 0x24), ("OR", 0x25),
                           ("XOR", 0x26), ("SRA", 0x03), ("SRL", 0x02), ("NOR", 0x27)):
            with self.subTest(operation=name):
                self.assertEqual(Request(5, 10, name).packet, bytes([0xCD, 5, 10, code]))
                self.assertLess(code, 64)
        self.assertEqual(Request(205, 205, "ADD").packet, b"\xcd\xcd\xcd\x20")

    def test_opcodes_match_original_alu_file(self):
        source = Path(__file__).resolve().parents[3] / "TP1/src/alu.v"
        codes = {name: int(bits, 2) for name, bits in
                 re.findall(r"localparam\s+(\w+)\s*=\s*6'b([01]{6})", source.read_text())}
        self.assertEqual(OPERATIONS, codes)

    def test_request_rejects_invalid_programmatic_values(self):
        for a, b, operation in ((256, 0, "ADD"), (-1, 0, "ADD"), (0, 1.5, "SUB"),
                                (True, 0, "ADD"), (0, 0, "MUL")):
            with self.subTest(values=(a, b, operation)), self.assertRaises(ValueError):
                Request(a, b, operation)

    def test_signed_display_preserves_byte(self):
        for value, expected in ((0, 0), (127, 127), (128, -128), (243, -13), (255, -1)):
            self.assertEqual(signed_byte(value), expected)


class SerialTests(unittest.TestCase):
    def setUp(self):
        self.port = FakePort()
        self.factory = Mock(return_value=self.port)
        self.client = AluConnection(self.factory)
        self.client.connect("COM_TEST")

    def tearDown(self):
        self.client.close()

    def test_port_configuration_is_9600_8n1_without_flow_control(self):
        self.factory.assert_called_once_with(
            port="COM_TEST", baudrate=9600, bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE, stopbits=serial.STOPBITS_ONE,
            timeout=1.5, write_timeout=1.0, xonxoff=False, rtscts=False, dsrdtr=False,
        )

    def test_binary_result_is_taken_from_port_not_recomputed(self):
        # Deliberately unrelated to 5+10: only the FPGA response is displayed.
        self.port.response = b"\xa7"
        self.assertEqual(self.client.exchange(Request(5, 10, "ADD")), 167)
        self.assertEqual(self.port.writes, [b"\xcd\x05\x0a\x20"])
        self.assertEqual(self.port.read_sizes, [1])

    def test_all_possible_response_bytes_including_zero_and_newlines(self):
        for byte in range(256):
            self.port.response = bytes([byte])
            self.assertEqual(self.client.exchange(Request(0, 0, "ADD")), byte)

    def test_timeout_closes_connection_and_does_not_retry(self):
        self.port.response = b""
        with self.assertRaisesRegex(CommunicationError, "reset"):
            self.client.exchange(Request(5, 10, "ADD"))
        self.assertFalse(self.port.is_open)
        self.assertEqual(len(self.port.writes), 1)
        with self.assertRaises(CommunicationError):
            self.client.exchange(Request(1, 2, "ADD"))
        self.assertEqual(len(self.port.writes), 1)

    def test_partial_write_aborts_without_read_or_retry(self):
        self.port.short_write = True
        with self.assertRaisesRegex(CommunicationError, "completa"):
            self.client.exchange(Request(5, 10, "ADD"))
        self.assertFalse(self.client.connected)
        self.assertEqual(self.port.read_sizes, [])
        self.assertEqual(len(self.port.writes), 1)

    def test_stale_response_is_not_assigned_to_next_operation(self):
        self.port.in_waiting = 1
        with self.assertRaisesRegex(CommunicationError, "ambigua"):
            self.client.exchange(Request(5, 10, "ADD"))
        self.assertEqual(self.port.writes, [])
        self.assertFalse(self.client.connected)

    def test_write_timeout_and_unplug_close_connection(self):
        self.port.write_error = serial.SerialTimeoutException("Write timed out")
        with self.assertRaises(CommunicationError):
            self.client.exchange(Request(5, 10, "ADD"))
        self.assertFalse(self.client.connected)
        self.port = FakePort()
        self.factory.return_value = self.port
        self.client.connect("COM_TEST")
        self.port.read_error = serial.SerialException("Device disconnected")
        with self.assertRaises(CommunicationError):
            self.client.exchange(Request(5, 10, "ADD"))
        self.assertFalse(self.client.connected)

    def test_unavailable_or_empty_port(self):
        self.factory.side_effect = serial.SerialException("Port busy")
        with self.assertRaisesRegex(CommunicationError, "abrir"):
            self.client.connect("COM_BUSY")
        self.assertFalse(self.client.connected)
        with self.assertRaises(CommunicationError):
            self.client.connect(" ")


class GuiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])
        cls.app.setQuitOnLastWindowClosed(False)

    def setUp(self):
        self.port = FakePort()
        self.worker = SerialWorker(AluConnection(Mock(return_value=self.port)))
        self.window = CalculatorWindow(self.worker)
        self.window.show()
        self.wait_until(lambda: self.window.refresh_button.isEnabled())

    def wait_until(self, predicate, timeout=2):
        deadline = time.monotonic() + timeout
        while not predicate() and time.monotonic() < deadline:
            QTest.qWait(10)
        self.assertTrue(predicate(), "Timed out waiting for Qt worker")

    def connect_port(self):
        self.window.port_combo.setEditText("COM_TEST")
        QTest.mouseClick(self.window.connect_button, Qt.MouseButton.LeftButton)
        self.wait_until(lambda: self.window.connected)

    def tearDown(self):
        if self.port.gate is not None:
            self.port.gate.set()
        self.window.close()
        self.wait_until(lambda: not self.worker.isRunning())
        self.app.processEvents()
        self.window.close()
        self.window.deleteLater()
        self.app.processEvents()

    def test_keypad_and_switch_operand(self):
        self.window.inputs[0].setFocus()
        self.window.inputs[0].selectAll()
        for digit in ("2", "5", "5"):
            button = next(b for b in self.window.key_buttons if b.text() == digit)
            QTest.mouseClick(button, Qt.MouseButton.LeftButton)
        self.assertEqual(self.window.inputs[0].text(), "255")
        QTest.mouseClick(self.window.switch_button, Qt.MouseButton.LeftButton)
        self.window.keypress("1")
        self.assertEqual(self.window.inputs[1].text(), "1")
        self.window.swap_operands()
        self.assertEqual([field.text() for field in self.window.inputs], ["1", "255"])

    def test_invalid_or_empty_operand_disables_sending_without_truncation(self):
        self.connect_port()
        for value in ("256", "1000", ""):
            self.window.inputs[0].setText(value)
            self.assertEqual(self.window.inputs[0].text(), value)
            self.assertTrue(all(not button.isEnabled() for button in self.window.operation_buttons.values()))
            self.window.calculate("ADD")
        self.assertEqual(self.port.writes, [])
        self.window.inputs[0].setText("255")
        self.assertTrue(self.window.operation_buttons["ADD"].isEnabled())

    def test_operation_buttons_send_correct_packets_and_display_response(self):
        self.connect_port()
        self.window.inputs[0].setText("5")
        self.window.inputs[1].setText("10")
        for operation, code in OPERATIONS.items():
            QTest.mouseClick(self.window.operation_buttons[operation], Qt.MouseButton.LeftButton)
            self.wait_until(lambda: not self.window.busy)
            self.assertEqual(self.port.writes[-1], bytes([0xCD, 5, 10, code]))
            self.assertEqual(self.window.result_label.text(), "15")
        self.assertEqual(len(self.port.writes), 8)

    def test_waiting_is_nonblocking_and_cannot_send_second_request(self):
        self.connect_port()
        self.port.gate = threading.Event()
        self.window.calculate("ADD")
        self.wait_until(lambda: len(self.port.writes) == 1)
        self.assertTrue(self.window.busy)
        self.assertFalse(self.window.connect_button.isEnabled())
        self.assertTrue(all(not button.isEnabled() for button in self.window.operation_buttons.values()))
        self.window.calculate("SUB")
        QTest.qWait(30)  # Qt processes events while the port is still waiting.
        self.assertEqual(len(self.port.writes), 1)
        self.port.gate.set()
        self.wait_until(lambda: not self.window.busy)

    def test_timeout_clears_previous_result_and_requires_reconnection(self):
        self.connect_port()
        self.window.calculate("ADD")
        self.wait_until(lambda: not self.window.busy)
        self.assertEqual(self.window.result_label.text(), "15")
        self.port.response = b""
        self.window.calculate("SUB")
        self.wait_until(lambda: not self.window.busy)
        self.assertFalse(self.window.connected)
        self.assertEqual(self.window.result_label.text(), "—")
        self.assertIn("reset", self.window.status_label.text())

    def test_close_during_receive_finishes_worker_and_closes_port(self):
        self.connect_port()
        self.port.gate = threading.Event()
        self.window.calculate("ADD")
        self.wait_until(lambda: len(self.port.writes) == 1)
        self.window.close()
        self.assertTrue(self.window.closing)
        self.port.gate.set()
        self.wait_until(lambda: not self.worker.isRunning())
        self.assertFalse(self.port.is_open)


if __name__ == "__main__":
    unittest.main(verbosity=2)
