addi x1, x0, 5
addi x2, x0, 0
loop: add x2, x2, x1
addi x1, x1, -1
bne x1, x0, loop
jal x31, end
sw x31, 0(x0)
end: sw x2, 4(x0)
halt
# x2=15, x31=24, DMEM[4]=15, DMEM[0]=0
