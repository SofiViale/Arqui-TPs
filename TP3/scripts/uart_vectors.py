"""Application-generated UART waveforms, checked through real RTL RX/TX and snapshot decoder."""
import struct
from pathlib import Path
from assembler import assemble
from protocol import COMMANDS,SCHEMA,Parser,frame
from snapshot import snapshot

def generate(build):
    tokens=[];expected=[];seq=0
    def send(cmd,payload=b'',error=0,check=None):
        nonlocal seq
        code=COMMANDS[cmd] if isinstance(cmd,str) else cmd
        tokens.extend(frame(code,seq,payload));tokens.append(256)
        expected.append((code|128,seq,error,check));seq=(seq+1)&255
    def load(asm):
        raw=struct.pack('<'+'I'*len(assemble(asm)),*assemble(asm))
        send('begin',struct.pack('<IIB',len(raw),0,0))
        for i in range(0,len(raw),128):send('data',struct.pack('<I',i)+raw[i:i+128])
        send('commit')
    def snap_regs(regs,cause=1,empty=True):
        def check(data):
            s=snapshot(data);h=s['header']
            assert h[4]==cause,(h,cause)
            if empty:assert h[6]==0,h
            for r,value in regs.items():assert s['registers'][r]==value&0xffffffff,(r,s['registers'][r],value)
            assert s['registers'][0]==0
        return check
    send('status',check=lambda d: assert_schema(d))
    send(0x55,error=1);send('run',error=5);send('step',b'bad',error=2)
    # Corrupt CRC, unknown version, malformed escape, then resynchronise.
    bad=bytearray(frame(1,42));bad[-2]^=1;tokens.extend(bad)
    tokens.extend(b'\x7e\x01\x7d\x7e')
    # Version and overlong command are rejected without architectural effects.
    from protocol import crc16
    wrong=b'\x02\x01\x00\x00\x00'
    tokens.extend(b'\x7e'+wrong+struct.pack('<H',crc16(wrong))+b'\x7e')
    send('status',bytes(512),error=2)
    send('status')
    tokens.extend(frame(3,43,bytes(range(32)))[:12]);tokens.append(257);send('status')
    send('begin',struct.pack('<IIB',8,0,0));send('data',struct.pack('<II',0,0x00100073))
    send('commit',error=5);send('run',error=5)
    demo=(Path(__file__).resolve().parents[1]/'programs/demo.asm').read_text()
    load(demo);send('run');send('status');send('snapshot',check=snap_regs({1:7,2:12,3:12,4:19,31:0}))
    send('memory',struct.pack('<II',0,4),check=lambda d: equal(d,struct.pack('<I',12)))
    send('memory',struct.pack('<II',1020,8),error=4)
    send('restart',b'\0')
    send('step');send('step');send('snapshot',check=lambda d: busy_snapshot(d))
    send('begin',struct.pack('<IIB',4,0,0),error=3)
    send('pause');send('step');send('snapshot',check=lambda d: step_snapshot(d))
    send('run');send('snapshot',check=snap_regs({4:19}))
    # A shorter image must never execute residue, and BEGIN clears DMEM by default.
    load('addi x31,x0,42\nhalt');send('run');send('snapshot',check=snap_regs({1:0,4:0,31:42}))
    send('memory',struct.pack('<II',0,128),check=lambda d: equal(d,bytes(128)))
    # CRC escaping in payload and response, x31 is a real architectural register.
    load('lui x31,0x7e7d8\naddi x31,x31,-643\nsw x31,0(x0)\nhalt')
    send('run');send('snapshot',check=snap_regs({31:0x7e7d7d7d}))
    send('memory',struct.pack('<II',0,4),check=lambda d: equal(d,bytes.fromhex('7d7d7d7e')))
    send('restart',b'\1');send('memory',struct.pack('<II',0,4),check=lambda d: equal(d,bytes.fromhex('7d7d7d7e')))
    send('restart',b'\0');send('memory',struct.pack('<II',0,4),check=lambda d: equal(d,bytes(4)))
    load('loop: jal x0,loop');send('limit',struct.pack('<I',20));send('run');send('snapshot',check=snap_regs({},cause=7))
    # Missing HALT / shorter program length yields fetch fault, not old words.
    load('addi x1,x0,3');send('limit',struct.pack('<I',1000));send('run');send('snapshot',check=snap_regs({1:3,31:0},cause=3))
    # Nonzero entry skips the initial instruction, while length still bounds fetch.
    raw=struct.pack('<3I',0x06300093,0x02a00f93,0x00100073)
    send('begin',struct.pack('<IIB',12,4,0));send('data',struct.pack('<I',0)+raw);send('commit')
    send('run');send('snapshot',check=snap_regs({1:0,31:42}))
    # Interrupted DATA after BEGIN keeps program invalid and permits a fresh BEGIN.
    send('begin',struct.pack('<IIB',8,0,0))
    tokens.extend(frame(3,99,struct.pack('<III',0,0x13,0x00100073))[:10]);tokens.append(257)
    send('run',error=5);load('halt');send('run');send('snapshot',check=snap_regs({1:0,31:0}))
    tokens.append(259)
    (build/'uart_input.txt').write_text('\n'.join(map(str,tokens)),encoding='ascii')
    return expected

def equal(got,want):assert got==want,(got,want)
def assert_schema(d):assert struct.unpack('<I',d[:4])[0]==SCHEMA
def busy_snapshot(d):
    h=snapshot(d)['header'];assert h[3]==2 and h[6]!=0 and h[1]==0,h

def step_snapshot(d):
    s=snapshot(d);h=s['header'];assert h[3]==3 and h[1]==0,h
    # Complete pipeline payload is transported, including the high PC/instruction fields.
    assert s['pipeline'][1]['instruction']==0x00508113,s

def verify(build,expected):
    raw=bytes(int(x,16) for x in (build/'uart_output.txt').read_text().split())
    packets=Parser().feed(raw)
    assert len(packets)==len(expected),(len(packets),len(expected))
    for index,((cmd,seq,payload),(want_cmd,want_seq,error,check)) in enumerate(zip(packets,expected)):
        assert (cmd,seq)==(want_cmd,want_seq),(index,cmd,seq)
        assert payload and payload[0]==error,(index,payload,error)
        if check:check(payload[1:])
    print(f'PASS: UART application/RTL roundtrip ({len(expected)} exchanges, {len(raw)} response bytes)')
