"""Assembler for the TP3 subset. Every source instruction emits exactly one word."""
import re
R = {'add':(0,0),'sub':(0,32),'sll':(1,0),'slt':(2,0),'sltu':(3,0),
     'xor':(4,0),'srl':(5,0),'sra':(5,32),'or':(6,0),'and':(7,0)}
I = {'addi':0,'slti':2,'sltiu':3,'xori':4,'ori':6,'andi':7}
LOAD = {'lb':0,'lh':1,'lw':2,'lbu':4,'lhu':5}
STORE = {'sb':0,'sh':1,'sw':2}
class AssemblyError(ValueError): pass

def reg(text):
    if not re.fullmatch(r'x(?:[0-9]|[12][0-9]|3[01])', text):
        raise ValueError(f'registro inválido: {text}; usar x0..x31')
    return int(text[1:])

def number(text):
    try:
        return int(text, 0) if re.match(r'[-+]?0[xXbBoO]', text) else int(text, 10)
    except ValueError:
        raise ValueError(f'entero inválido: {text}') from None

def signed(value, bits):
    if not -(1 << (bits-1)) <= value < (1 << (bits-1)):
        raise ValueError(f'inmediato {value} fuera del rango signed de {bits} bits')
    return value & ((1 << bits)-1)

def encode(op, args, pc, labels):
    def arity(n):
        if len(args) != n: raise ValueError(f'{op} requiere {n} operandos, recibió {len(args)}')
    def offset(text,bits):
        val = labels[text]-pc if text in labels else number(text)
        if val % 4: raise ValueError('destino sin alinear a 4 bytes')
        return signed(val,bits)
    if op in ('nop','halt'):
        arity(0); return 0x13 if op=='nop' else 0x00100073
    if op in R:
        arity(3); d,a,b=map(reg,args); f,g=R[op]
        return g<<25|b<<20|a<<15|f<<12|d<<7|0x33
    if op in I or op in ('slli','srli','srai'):
        arity(3); d,a=map(reg,args[:2]); v=number(args[2])
        if op in I: v=signed(v,12);f=I[op]
        else:
            if not 0<=v<=31: raise ValueError('shamt debe estar entre 0 y 31')
            f=1 if op=='slli' else 5
            if op=='srai': v|=0x400
        return v<<20|a<<15|f<<12|d<<7|0x13
    if op in LOAD or op in STORE or op=='jalr':
        arity(2);d=reg(args[0]);m=re.fullmatch(r'([^()]+)\((x\d+)\)',args[1])
        if not m: raise ValueError('usar inmediato(xN), por ejemplo 4(x2)')
        v=signed(number(m[1]),12);a=reg(m[2])
        if op in STORE:return (v>>5)<<25|d<<20|a<<15|STORE[op]<<12|(v&31)<<7|0x23
        return v<<20|a<<15|(LOAD.get(op,0))<<12|d<<7|(0x67 if op=='jalr' else 3)
    if op in ('beq','bne'):
        arity(3);a,b=map(reg,args[:2]);v=offset(args[2],13)
        return ((v>>12)&1)<<31|((v>>5)&63)<<25|b<<20|a<<15|(op=='bne')<<12|((v>>1)&15)<<8|((v>>11)&1)<<7|0x63
    if op=='jal':
        arity(2);d=reg(args[0]);v=offset(args[1],21)
        return ((v>>20)&1)<<31|((v>>1)&1023)<<21|((v>>11)&1)<<20|((v>>12)&255)<<12|d<<7|0x6f
    if op=='lui':
        arity(2);d=reg(args[0]);v=number(args[1])
        if not 0<=v<=0xfffff: raise ValueError('LUI requiere un campo unsigned de 20 bits')
        return v<<12|d<<7|0x37
    raise ValueError(f'instrucción no soportada: {op}')

def assemble(source):
    labels={};lines=[];pc=0
    for line_no,line in enumerate(source.splitlines(),1):
        line=re.split(r'#|;',line,maxsplit=1)[0].strip().lower()
        try:
            while ':' in line:
                label,line=line.split(':',1);label=label.strip();line=line.strip()
                if not re.fullmatch(r'[a-z_][a-z_0-9]*',label):raise ValueError('etiqueta inválida')
                if label in labels:raise ValueError(f'etiqueta duplicada: {label}')
                labels[label]=pc
            if line:lines.append((line_no,pc,line));pc+=4
        except ValueError as e:raise AssemblyError(f'línea {line_no}: {e}') from None
    words=[]
    for line_no,pc,line in lines:
        try:
            parts=line.split(None,1);op=parts[0]
            args=[re.sub(r'\s+','',x) for x in parts[1].split(',')] if len(parts)>1 else []
            words.append(encode(op,args,pc,labels))
        except ValueError as e:raise AssemblyError(f'línea {line_no}: {e}') from None
    if not words:raise AssemblyError('programa vacío')
    return words
