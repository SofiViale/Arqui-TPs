"""Directed expected values, independent of the RTL decoder/ALU."""
CASES=[]
def add(name,asm,regs=None,mem=None,cause=1,limit=1000,stalls=None):
    CASES.append(dict(name=name,asm=asm,regs=regs or {},mem=mem or {},cause=cause,limit=limit,stalls=stalls))
add('demo','addi x1,x0,7\naddi x2,x1,5\nsw x2,0(x0)\nlw x3,0(x0)\nadd x4,x3,x1\nhalt',{1:7,2:12,3:12,4:19},{0:12},stalls=1)
for op,result in [('add',-13),('sub',-19),('sll',0xffffff80),('srl',0x1ffffffe),('sra',-2),('and',0),('or',0xfffffff3),('xor',0xfffffff3),('slt',1),('sltu',0)]:
    add(op,f'addi x1,x0,-16\naddi x2,x0,3\n{op} x31,x1,x2\nhalt',{1:-16,2:3,31:result})
for op,val,result in [('addi',-1,-17),('andi',15,0),('ori',3,0xfffffff3),('xori',-1,15),('slti',-1,1),('sltiu',-1,1),('slli',31,0),('srli',31,1),('srai',31,-1)]:
    add(op,f'addi x1,x0,-16\n{op} x31,x1,{val}\nhalt',{1:-16,31:result})
add('lui','lui x31,0xabcde\naddi x1,x31,1\nhalt',{31:0xabcde000,1:0xabcde001})
add('successive_sources_x0','addi x1,x0,1\naddi x1,x1,2\nadd x2,x1,x1\naddi x0,x2,99\nadd x31,x0,x2\nhalt',{1:3,2:6,31:6})
add('wb_id','addi x1,x0,7\naddi x2,x0,3\naddi x3,x0,9\nadd x31,x1,x1\nhalt',{1:7,2:3,3:9,31:14})
add('load_store_base_data','addi x1,x0,16\nsw x1,0(x0)\nlw x2,0(x0)\nsw x2,0(x2)\nlw x3,16(x0)\nadd x4,x3,x2\nhalt',{1:16,2:16,3:16,4:32},{0:16,16:16},stalls=2)
add('false_load_use','lw x1,0(x0)\naddi x2,x0,1\nhalt',{2:1},stalls=0)
add('bytes','addi x1,x0,-128\nsb x1,1(x0)\nlb x2,1(x0)\nlbu x3,1(x0)\naddi x4,x0,-1\nsh x4,2(x0)\nlh x5,2(x0)\nlhu x6,2(x0)\nlw x7,0(x0)\nhalt',{1:-128,2:-128,3:128,4:-1,5:-1,6:65535,7:0xffff8000},{0:0xffff8000})
add('neighbors','lui x1,0x12345\naddi x1,x1,0x678\nsw x1,0(x0)\naddi x2,x0,-1\nsb x2,1(x0)\nsh x2,2(x0)\nlw x3,0(x0)\nhalt',{1:0x12345678,2:-1,3:0xffffff78},{0:0xffffff78})
add('loop','addi x1,x0,5\nloop: add x2,x2,x1\naddi x1,x1,-1\nbne x1,x0,loop\nbeq x2,x0,bad\njal x31,end\nbad: sw x2,0(x0)\nend: sw x2,4(x0)\nhalt',{2:15,31:24},{4:15})
add('flush_halt_illegal','jal x1,good\nhalt\n.wordbad\ngood: addi x2,x1,3\nhalt',{1:4,2:7})
add('flush_store_wb','addi x1,x0,7\nbeq x1,x1,good\nsw x1,0(x0)\naddi x2,x0,99\ngood: halt',{1:7})
add('load_branch','addi x1,x0,1\nsw x1,0(x0)\nlw x2,0(x0)\nbeq x2,x1,good\nhalt\ngood: addi x31,x0,8\nhalt',{1:1,2:1,31:8},{0:1},stalls=1)
add('jalr_alu','addi x1,x0,17\njalr x31,0(x1)\nsw x1,0(x0)\nhalt\naddi x2,x31,1\nhalt',{1:17,31:8,2:9})
add('jalr_load','addi x1,x0,25\nsw x1,0(x0)\nlw x2,0(x0)\njalr x31,0(x2)\nhalt\nsw x1,4(x0)\naddi x3,x31,1\nhalt',{1:25,2:25,31:16,3:17},{0:25},stalls=1)
add('misaligned_target','addi x1,x0,6\njalr x2,0(x1)\naddi x3,x0,9\nhalt',{1:6},cause=6)
for op,addr,cause in [('lw',1,4),('lh',3,4),('sw',2,4),('sh',1,4),('lw',1024,5),('lb',-1,5),('sw',1024,5),('sh',1024,5)]:
    add(f'error_{op}_{addr}',f'addi x1,x0,7\n{op} x2,{addr}(x0)\naddi x3,x0,99\nhalt',{1:7},cause=cause)
add('last_byte','addi x1,x0,127\nsb x1,1023(x0)\nlbu x2,1023(x0)\nhalt',{1:127,2:127},{1020:0x7f000000})
add('illegal_precise','addi x1,x0,7\n.wordbad\nsw x1,0(x0)\nhalt',{1:7},cause=2)
add('no_halt','addi x1,x0,7',{1:7},cause=3)
add('watchdog','loop: jal x0,loop',cause=7,limit=25)
add('watchdog_last_halt','halt',cause=7,limit=3)
add('mem_older_halt','lw x1,1(x0)\nhalt',cause=4)
add('halt_stops_store','addi x1,x0,7\nhalt\nsw x1,0(x0)',{1:7})

add('watchdog_preserves_edge','addi x1,x0,7\nsw x1,0(x0)\nhalt',{1:7},{0:7},cause=7,limit=5)
