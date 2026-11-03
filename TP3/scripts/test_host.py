"""Host tests: independent encodings, malformed input, protocol integrity and schema."""
import struct,sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'pc'))
from assembler import assemble,AssemblyError
from protocol import crc16,frame,Parser,SCHEMA
from snapshot import FIELDS,WIDTHS,snapshot,format_snapshot
from tp3 import Client

class AssemblerTests(unittest.TestCase):
 def test_demo_exact(self):
  self.assertEqual(assemble('addi x1,x0,7\naddi x2,x1,5\nsw x2,0(x0)\nlw x3,0(x0)\nadd x4,x3,x1\nhalt'),
   [0x00700093,0x00508113,0x00202023,0x00002183,0x00118233,0x00100073])
 def test_labels(self):
  self.assertEqual(assemble('start: nop\nbeq x0,x0,start\njal x31,start'),[0x13,0xfe000ee3,0xff9fffef])
 def test_immediate_boundaries(self):
  self.assertEqual(assemble('addi x31,x0,-2048\nsrai x31,x31,31\nlui x31,0xfffff'),[0x80000f93,0x41ffdf93,0xffffffb7])
 def test_reject(self):
  for source in ['add x32,x0,x0','addi x1,x0,2048','addi x1,x0,-2049','slli x1,x1,32','srai x1,x0,-1',
                 'beq x0,x0,2','beq x0,x0,4096','jal x1,1048576','lui x1,-1','lui x1,0x100000',
                 'jal x1,missing','a:nop\na:halt','mul x1,x2,x3','li x31,7','nop x1','lw x1,4','jalr x1,x2,0','add x1 x2 x3']:
   with self.subTest(source=source),self.assertRaisesRegex(AssemblyError,'línea'):assemble(source)
 def test_x31_not_reserved(self):
  self.assertEqual(assemble('add x31,x31,x31'),[0x01ff8fb3])

class ProtocolTests(unittest.TestCase):
 def test_known_crc(self):self.assertEqual(crc16(b'123456789'),0x4b37)
 def test_all_bytes_escaped(self):
  raw=bytes(range(256));packet=frame(3,0x7e,raw);parser=Parser();answers=[]
  for b in packet:answers+=parser.feed(bytes([b]))
  self.assertEqual(answers,[(3,0x7e,raw)])
 def test_bad_and_resync(self):
  bad=bytearray(frame(1,5));bad[-2]^=1
  parser=Parser();self.assertEqual(parser.feed(bad),[])
  self.assertEqual(parser.feed(b'\x7e\x01\x7d\x7e'+frame(1,6)),[(1,6,b'')])
 def test_oversize(self):
  with self.assertRaises(ValueError):frame(3,0,bytes(513))
 def test_snapshot_all_fields(self):
  h=[SCHEMA,0,12,3,0,0,15,0,0,0,0,24,0,1000,0,1]
  raw=struct.pack('<16I',*h)+struct.pack('<32I',*range(32))
  for w in WIDTHS:raw+=((1<<w)-1).to_bytes((w+7)//8,'little')
  parsed=snapshot(raw)
  for fields,values in zip(FIELDS,parsed['pipeline']):
   for key,w in fields:self.assertEqual(values[key],(1<<w)-1)
  self.assertIn('x31: 0x0000001f',format_snapshot(raw));self.assertEqual(len(raw),256)
 def test_schema_matches_rtl(self):
  import re
  text=(Path(__file__).resolve().parents[1]/'rtl/processor.v').read_text()
  for name,width in zip(('fi','ix','xm','mw'),WIDTHS):self.assertRegex(text,rf'\[{width-1}:0\] {name}\b')
  self.assertEqual(WIDTHS,(64,196,141,103))

if __name__=='__main__':unittest.main()
