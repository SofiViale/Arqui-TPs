#!/usr/bin/env python3
"""Run accumulated TP3 RTL regression using Vivado xsim (or legacy Icarus runner)."""
import argparse,json,os,shutil,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];TP3=ROOT/'TP3';BUILD=TP3/'build'
sys.path.insert(0,str(TP3/'pc'))
from assembler import assemble
from test_cases import CASES
from simulate import BENCHES
FULL=['alu_adapter','decoder','immediate','register_file','imem','dmem','processor']
SYSTEM=FULL+['packet','debug','system']

def vivado_bin(value=None):
    if value:return Path(value)
    found=shutil.which('xvlog') or shutil.which('xvlog.bat')
    if found:return Path(found).parent
    for base in ('C:/AMDDesignTools','C:/Xilinx','C:/Xilinx/Vivado','/opt/Xilinx/Vivado'):
        for path in sorted(Path(base).glob('**/bin/xvlog.bat'),reverse=True):return path.parent
    raise RuntimeError('xvlog no encontrado: indicar --vivado-bin <Vivado/bin>')

def generate_cases():
    lines=[]
    for c in CASES:
        src=c['asm'];bad_indices=[i for i,line in enumerate(src.splitlines()) if '.wordbad' in line]
        words=assemble(src.replace('.wordbad','nop'))
        for i in bad_indices:words[i]=0xffffffff
        for mode in (0,1):
            lines.append(f'$display("CASE {c["name"]} mode={mode}");')
            lines.append(f'begin_program({len(words)*4},{c["limit"]});')
            lines.extend(f'put({i*4},32\'h{word:08x});' for i,word in enumerate(words))
            lines.append(f'execute({mode}); check(cause=={c["cause"]},"stop cause");')
            lines.extend(f'regcheck({i},32\'h{c["regs"].get(i,0)&0xffffffff:08x});' for i in range(32))
            lines.extend(f'memcheck({i},32\'h{c["mem"].get(i,0)&0xffffffff:08x});' for i in range(0,1024,4))
            if c['stalls'] is not None:lines.append(f'check(stalls=={c["stalls"]},"load-use stall count");')
    (BUILD/'processor_cases.vh').write_text('\n'.join(lines)+'\n',encoding='ascii')

def sources(bench):
    if bench in BENCHES:names=[x[:-2] for x in BENCHES[bench]]
    elif bench=='processor_tb':names=FULL
    elif bench in ('uart_system_tb','uart_baud_tb','board_tb'):names=SYSTEM+(['basys3_top'] if bench=='board_tb' else [])
    else:raise ValueError(bench)
    paths=[TP3/'rtl'/f'{name}.v' for name in names]
    if 'alu_adapter' in names:paths.insert(0,ROOT/'TP1/src/alu.v')
    if 'system' in names:paths.extend(ROOT/'TP2/src'/f'{n}.v' for n in ['baud_rate_generator','uart_rx','uart_tx','reset_sync'])
    return paths+[TP3/'tb'/f'{bench}.v']

def run_command(command,cwd,log,timeout=180):
    p=subprocess.run([str(x) for x in command],cwd=cwd,capture_output=True,text=True,errors='replace',timeout=timeout)
    out=p.stdout+p.stderr;(cwd/log).write_text(out,encoding='utf-8')
    if p.returncode or 'ERROR:' in out:
        print(out[-12000:]);raise RuntimeError(f'falló {Path(command[0]).name}, código {p.returncode}; ver {cwd/log}')
    return out

def simulate_bench(bench,binpath):
    work=BUILD/'xsim'/bench;work.mkdir(parents=True,exist_ok=True)
    ext='.bat' if os.name=='nt' else ''
    src=sources(bench)
    includes=['--include',TP3/'rtl','--include',TP3/'tb','--include',BUILD]
    run_command([binpath/('xvlog'+ext),*includes,*src[:-1]],work,'compile.log')
    run_command([binpath/('xvlog'+ext),'--sv',*includes,src[-1]],work,'compile_tb.log')
    run_command([binpath/('xelab'+ext),bench,'-s','test','--debug','typical'],work,'elaborate.log')
    cmd=[binpath/('xsim'+ext),'test','-runall']
    if bench=='pipeline_tb':cmd+=['-testplusarg','TRACE='+str(BUILD/'pipeline_trace_current.csv')]
    if bench=='uart_system_tb':cmd+=['-testplusarg','INPUT='+str(BUILD/'uart_input.txt'),'-testplusarg','OUTPUT='+str(BUILD/'uart_output.txt')]
    # An option file avoids Windows batch splitting of '=' in plusargs.
    options=work/'xsim.args'
    options.write_text('\n'.join(chr(34)+str(x).replace(chr(92),'/')+chr(34) for x in cmd[2:]),encoding='ascii')
    out=run_command([cmd[0],cmd[1],'--file',options],work,'simulate.log',timeout=240)
    if f'PASS: {bench}' not in out or 'FAIL' in out or 'Fatal:' in out:
        print(out[-10000:]);raise RuntimeError(f'{bench} sin PASS válido')
    print('\n'.join(line for line in out.splitlines() if 'PASS:' in line))
    return out

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--vivado-bin');parser.add_argument('--bench',choices=list(BENCHES)+['processor_tb','uart_system_tb','uart_baud_tb','board_tb']);args=parser.parse_args()
    BUILD.mkdir(exist_ok=True);generate_cases();results={}
    try:
        binpath=vivado_bin(args.vivado_bin)
        benches=[args.bench] if args.bench else list(BENCHES)+['processor_tb','uart_system_tb','uart_baud_tb','board_tb']
        for bench in benches:
            print('Running',bench,flush=True)
            if bench=='uart_system_tb':
                from uart_vectors import generate,verify
                expected=generate(BUILD)
            simulate_bench(bench,binpath)
            if bench=='uart_system_tb':verify(BUILD,expected)
            results[bench]='PASS'
    except (RuntimeError,subprocess.TimeoutExpired,OSError,AssertionError,ValueError) as e:
        print('FAIL:',e,file=sys.stderr);results[locals().get('bench','setup')]='FAIL'
    report=BUILD/(f'regression_{args.bench}.json' if args.bench else 'regression.json')
    report.write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')
    return 0 if results and all(x=='PASS' for x in results.values()) else 1
if __name__=='__main__':sys.exit(main())
