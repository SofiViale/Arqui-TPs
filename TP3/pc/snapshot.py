"""Decoded snapshot schema 0x33545031; fields are MSB first as in RTL concatenations."""
import struct
from protocol import SCHEMA
FIELDS = [
 [('pc',32),('instruction',32)],
 [('pc',32),('instruction',32),('rs1',5),('rs2',5),('rd',5),('operand1',32),('operand2',32),('immediate',32),
  ('uses_rs1',1),('uses_rs2',1),('alu_op',4),('src_a',2),('src_b_imm',1),('reg_write',1),('mem_read',1),('mem_write',1),
  ('wb_sel',2),('mem_size',2),('load_unsigned',1),('branch_type',3),('is_halt',1)],
 [('pc',32),('instruction',32),('rd',5),('result',32),('store_data',32),('reg_write',1),('mem_read',1),('mem_write',1),
  ('mem_size',2),('load_unsigned',1),('wb_from_mem',1),('is_halt',1)],
 [('pc',32),('instruction',32),('rd',5),('write_data',32),('reg_write',1),('is_halt',1)]]
WIDTHS = tuple(sum(w for _,w in fields) for fields in FIELDS)
STATES = ['pausado','ejecutando','drenando','finalizado','error']
CAUSES = ['ninguna','HALT','instrucción ilegal','fetch fuera de programa/alineación',
          'DMEM desalineada','DMEM fuera de rango','salto desalineado','watchdog']
def signed32(value):return value-(1<<32) if value&0x80000000 else value

def snapshot(data):
    if len(data)!=256:raise ValueError(f'snapshot de {len(data)} bytes, se requieren 256')
    header=struct.unpack('<16I',data[:64])
    if header[0]!=SCHEMA:raise ValueError('schema de snapshot incompatible')
    if (header[1]>4 or header[4]>7 or header[6]>15 or header[7]>7 or
        any(header[i]>1 for i in (8,14,15))):raise ValueError('estado/flags de snapshot inválidos')
    regs=struct.unpack('<32I',data[64:192]);offset=192;stages=[]
    for fields,width in zip(FIELDS,WIDTHS):
        size=(width+7)//8;raw=int.from_bytes(data[offset:offset+size],'little');offset+=size
        if raw>>width:raise ValueError('padding de snapshot no nulo')
        values={};shift=width
        for name,w in fields:shift-=w;values[name]=(raw>>shift)&((1<<w)-1)
        stages.append(values)
    return dict(header=header,registers=regs,pipeline=stages)

def format_snapshot(data):
    s=snapshot(data);h=s['header'];lines=[f'Estado: {STATES[h[1]]}  PC=0x{h[2]:08x}  ciclos={h[3]}',
    f'Causa: {CAUSES[h[4]]}  PC de parada/error=0x{h[5]:08x}  flags de excepción=0x{h[7]:x}',
    f'Programa: {h[11]} bytes, entrada=0x{h[12]:08x}, límite={h[13]}, válido={h[15]}']
    for i,v in enumerate(s['registers']):lines.append(f'x{i:02}: 0x{v:08x}  unsigned={v:10d} signed={signed32(v):11d}')
    for i,(name,stage) in enumerate(zip(('IF/ID','ID/EX','EX/MEM','MEM/WB'),s['pipeline'])):
        lines.append(f'{name} valid={(h[6]>>i)&1}: '+', '.join(f'{k}=0x{v:x}' for k,v in stage.items()))
    lines.append(f'Memoria utilizada: 0x{h[9]:08x}..0x{h[10]:08x} (ambos extremos incluidos)' if h[8] else 'Memoria utilizada: sin accesos')
    return '\n'.join(lines)
