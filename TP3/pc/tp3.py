#!/usr/bin/env python3
"""CLI del procesador TP3, UART 8N1, una solicitud pendiente."""
import argparse
import struct
import sys
import time
from pathlib import Path
from assembler import assemble
from protocol import COMMANDS,ERRORS,SCHEMA,Parser,frame
from snapshot import WIDTHS,STATES,CAUSES,format_snapshot,snapshot,signed32

class Client:
    def __init__(self, transport, baud=9600):
        self.transport=transport;self.baud=baud;self.seq=0;self.parser=Parser()
    def request(self,cmd,payload=b''):
        command=COMMANDS[cmd];seq=self.seq;self.seq=(seq+1)&255
        packet=frame(command,seq,payload)
        self.transport.write(packet);self.transport.flush()
        # Worst-case escaping, 8N1, maximum response plus request and device work.
        deadline=time.monotonic()+2+2*(len(packet)+2*519+2)*10/self.baud
        while time.monotonic()<deadline:
            for got_cmd,got_seq,body in self.parser.feed(self.transport.read(1)):
                if (got_cmd,got_seq)!=(command|0x80,seq):continue
                if not body:raise RuntimeError('respuesta sin status')
                if body[0]:raise RuntimeError(ERRORS.get(body[0],f'error {body[0]}'))
                return body[1:]
        self.parser.reset()
        raise TimeoutError('UART sin respuesta válida; no se reintenta automáticamente una orden con efectos')
    def status(self):
        body=self.request('status')
        if len(body)!=44:raise RuntimeError('capacidades incompatibles')
        values=struct.unpack('<11I',body)
        if values[0]!=SCHEMA or tuple(values[4:8])!=WIDTHS or values[2]!=512:
            raise RuntimeError('RTL/aplicación incompatibles (schema/anchos/protocolo)')
        return values
    def load(self,words,entry=0,preserve=False):
        cap=self.status();raw=struct.pack('<'+'I'*len(words),*words)
        if len(raw)>cap[1] or entry%4 or not 0<=entry<len(raw):raise ValueError('tamaño/entrada de programa inválidos')
        self.request('begin',struct.pack('<IIB',len(raw),entry,preserve))
        for offset in range(0,len(raw),cap[3]):self.request('data',struct.pack('<I',offset)+raw[offset:offset+cap[3]])
        self.request('commit')
    def memory(self,address,count):
        if not 0<=address<=0xffffffff or count>0xffffffff or address+count>0x100000000 or address%4 or count%4 or count<=0:raise ValueError('dirección y cantidad deben ser múltiplos de 4; cantidad positiva')
        result=bytearray()
        for start in range(address,address+count,128):result+=self.request('memory',struct.pack('<II',start,min(128,address+count-start)))
        return bytes(result)

def show_memory(address,data):
    for offset in range(0,len(data),4):
        chunk=data[offset:offset+4];v=int.from_bytes(chunk,'little')
        print(f'0x{address+offset:08x}: {chunk.hex(" ")}  0x{v:08x}  u={v} s={signed32(v)}')

def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--port');p.add_argument('--baud',type=int,default=9600)
    sub=p.add_subparsers(dest='cmd',required=True)
    a=sub.add_parser('assemble');a.add_argument('file',type=Path);a.add_argument('-o','--output',type=Path)
    sub.add_parser('ports');sub.add_parser('status');sub.add_parser('pause')
    a=sub.add_parser('load');a.add_argument('file',type=Path);a.add_argument('--entry',type=lambda x:int(x,0),default=0);a.add_argument('--preserve-data',action='store_true')
    a=sub.add_parser('run');a.add_argument('--wait',action='store_true');a.add_argument('--timeout',type=float,default=30)
    a=sub.add_parser('step');a.add_argument('--count',type=int,default=1)
    a=sub.add_parser('restart');a.add_argument('--preserve-data',action='store_true')
    a=sub.add_parser('snapshot');a.add_argument('--used-memory',action='store_true')
    a=sub.add_parser('memory');a.add_argument('address',type=lambda x:int(x,0));a.add_argument('count',type=lambda x:int(x,0))
    a=sub.add_parser('limit');a.add_argument('cycles',type=lambda x:int(x,0))
    args=p.parse_args(argv)
    try:
        if args.cmd=='assemble':
            words=assemble(args.file.read_text(encoding='utf-8-sig'));out=''.join(f'{w:08x}\n' for w in words)
            if args.output:args.output.write_text(out,encoding='ascii')
            else:print(out,end='')
            return 0
        import serial
        if args.cmd=='ports':
            from serial.tools.list_ports import comports
            for port in comports():print(port.device,port.description)
            return 0
        if not args.port:p.error('--port es obligatorio para comunicar con la placa')
        if args.baud<=0:raise ValueError('baud debe ser positivo')
        with serial.Serial(args.port,args.baud,timeout=0.1,write_timeout=5) as transport:
            client=Client(transport,args.baud);cap=client.status()
            if args.cmd=='status':
                state=cap[8]&7;cause=(cap[8]>>8)&255
                print(f'{STATES[state]} PC=0x{cap[9]:08x} ciclos={cap[10]} causa={CAUSES[cause]} programa_válido={(cap[8]>>3)&1}; IMEM/DMEM={cap[1]} bytes; schema=0x{cap[0]:08x}')
            elif args.cmd=='load':
                words=assemble(args.file.read_text(encoding='utf-8-sig'));client.load(words,args.entry,args.preserve_data);print(f'Cargadas {len(words)} instrucciones; núcleo pausado.')
            elif args.cmd=='run':
                client.request('run')
                if args.wait:
                    deadline=time.monotonic()+args.timeout
                    while True:
                        cap=client.status()
                        if (cap[8]&7) in (3,4):break
                        if time.monotonic()>deadline:raise TimeoutError('espera de RUN agotada; consultar status o pausar')
                        time.sleep(0.05)
                    data=client.request('snapshot');print(format_snapshot(data))
                    if snapshot(data)['header'][1]==4:return 1
                else:print('RUN aceptado')
            elif args.cmd=='step':
                if args.count<1:raise ValueError('--count debe ser positivo')
                for _ in range(args.count):client.request('step')
                print(format_snapshot(client.request('snapshot')))
            elif args.cmd=='restart':client.request('restart',bytes([args.preserve_data]));print('Ejecución reiniciada y pausada')
            elif args.cmd=='snapshot':
                data=client.request('snapshot');print(format_snapshot(data));h=snapshot(data)['header']
                if args.used_memory and h[8]:
                    start=h[9]&~3;end=(h[10]+4)&~3;show_memory(start,client.memory(start,end-start))
            elif args.cmd=='memory':show_memory(args.address,client.memory(args.address,args.count))
            elif args.cmd=='limit':
                if not 0<=args.cycles<=0xffffffff:raise ValueError('límite fuera de uint32')
                client.request('limit',struct.pack('<I',args.cycles));print('Límite actualizado')
            else:client.request(args.cmd);print('OK')
        return 0
    except (ValueError,RuntimeError,TimeoutError,OSError,ImportError) as e:
        print(f'ERROR: {e}',file=sys.stderr);return 1
if __name__=='__main__':sys.exit(main())
