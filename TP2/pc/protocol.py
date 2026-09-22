"""Byte protocol shared with TP2/src/rx_interface_fsm.v."""

from dataclasses import dataclass


OPERATIONS = {
    "ADD": 0b100000,
    "SUB": 0b100010,
    "AND": 0b100100,
    "OR": 0b100101,
    "XOR": 0b100110,
    "SRA": 0b000011,
    "SRL": 0b000010,
    "NOR": 0b100111,
}

DESCRIPTIONS = {
    "ADD": "Suma A + B; el resultado conserva 8 bits.",
    "SUB": "Resta A − B; los negativos se representan en complemento a dos.",
    "AND": "AND bit a bit entre A y B.",
    "OR": "OR bit a bit entre A y B.",
    "XOR": "XOR bit a bit entre A y B.",
    "SRA": "Desplaza A a la derecha B posiciones, conservando su bit de signo.",
    "SRL": "Desplaza A a la derecha B posiciones, introduciendo ceros.",
    "NOR": "Invierte el resultado de OR bit a bit entre A y B.",
}


def parse_operand(text: str) -> int:
    """Accept decimal bytes; never wrap, clamp or silently truncate input."""
    value = text.strip()
    if not value or not value.isascii() or not value.isdecimal():
        raise ValueError("Ingresá un entero decimal entre 0 y 255.")
    significant = value.lstrip("0") or "0"
    if len(significant) > 3 or int(significant) > 255:
        raise ValueError("El máximo de 8 bits es 255. Corregí el operando.")
    return int(significant)


def signed_byte(value: int) -> int:
    return value if value < 128 else value - 256


@dataclass(frozen=True)
class Request:
    a: int
    b: int
    operation: str

    def __post_init__(self):
        if any(type(value) is not int or not 0 <= value <= 255 for value in (self.a, self.b)):
            raise ValueError("A y B deben ser enteros entre 0 y 255.")
        if self.operation not in OPERATIONS:
            raise ValueError("Operación no reconocida.")

    @property
    def packet(self) -> bytes:
        # OP is six bits, carried in a byte with its upper two bits cleared.
        return bytes((0xCD, self.a, self.b, OPERATIONS[self.operation]))

    @property
    def expression(self) -> str:
        return f"{self.a} {self.operation} {self.b}"
