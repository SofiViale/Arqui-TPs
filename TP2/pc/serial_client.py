"""Synchronous serial transactions; called exclusively from the GUI worker."""

import serial

from protocol import Request


class CommunicationError(Exception):
    pass


class AluConnection:
    def __init__(self, serial_factory=serial.Serial):
        self._factory = serial_factory
        self._port = None

    @property
    def connected(self):
        return self._port is not None and self._port.is_open

    def connect(self, port_name: str):
        self.close()
        if not port_name.strip():
            raise CommunicationError("Seleccioná un puerto serie.")
        try:
            self._port = self._factory(
                port=port_name.strip(), baudrate=9600,
                bytesize=serial.EIGHTBITS, parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE, timeout=1.5, write_timeout=1.0,
                xonxoff=False, rtscts=False, dsrdtr=False,
            )
            self._port.reset_input_buffer()
        except (serial.SerialException, OSError, ValueError) as error:
            self.close()
            raise CommunicationError(f"No se pudo abrir {port_name}: {error}") from error

    def close(self):
        port, self._port = self._port, None
        if port is not None:
            try:
                port.close()
            except (serial.SerialException, OSError):
                pass

    def exchange(self, request: Request) -> int:
        if not self.connected:
            raise CommunicationError("Primero conectá el puerto serie.")
        try:
            if self._port.in_waiting:
                raise CommunicationError("Llegaron bytes fuera de una operación; la respuesta sería ambigua.")
            written = self._port.write(request.packet)
            if written != len(request.packet):
                raise CommunicationError("La solicitud no pudo enviarse completa.")
            # Read exactly one binary byte, including 00, 0A, 0D and FF.
            # No readline(), ASCII conversion, software ALU or automatic retry.
            response = self._port.read(1)
            if len(response) != 1:
                raise CommunicationError("La FPGA no respondió dentro de 1,5 segundos.")
            return response[0]
        except (serial.SerialException, OSError, CommunicationError) as error:
            self.close()
            raise CommunicationError(
                f"{error} Se cerró el puerto. Revisá la conexión, aplicá reset a la FPGA "
                "y volvé a conectar antes de reenviar."
            ) from error
