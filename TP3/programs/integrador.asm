addi x1, x0, 7
addi x1, x1, 5
add x2, x1, x1
sw x2, 0(x0)
lw x3, 0(x0)
add x4, x3, x1
beq x4, x0, fallo
addi x5, x0, 36
beq x4, x5, correcto
sw x1, 4(x0)
fallo: addi x6, x0, 99
correcto: jal x31, fin
sw x1, 8(x0)
fin: sw x4, 12(x0)
halt