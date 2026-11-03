addi x1, x0, -128
sb x1, 1(x0)
lb x2, 1(x0)
lbu x3, 1(x0)
addi x4, x0, -1
sh x4, 2(x0)
lh x5, 2(x0)
lhu x6, 2(x0)
lw x7, 0(x0)
halt
# x2=ffffff80 x3=128 x5=ffffffff x6=65535 x7=ffff8000
