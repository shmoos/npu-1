#!/usr/bin/env python3
"""Fresh build in a space-free temporary directory; fail closed, preserve logs."""
import argparse, hashlib, json, os, platform, shutil, subprocess, tempfile, time
from pathlib import Path
from datetime import datetime, timezone
from importlib.metadata import version
ROOT=Path(__file__).resolve().parents[1]
RTL=['npu_pkg','mac_pe','skew_feeder','systolic_array_4x4','operand_buffer','tile_controller','postprocess','result_buffer','npu_core','npu_axil']
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--only', choices=['lint','test-pe','test-array','test-core','test-axil','demo']);args=ap.parse_args()
    os.chdir(ROOT); logdir=ROOT/'artifacts/verification';logdir.mkdir(parents=True,exist_ok=True)
    report={'timestamp_utc':datetime.now(timezone.utc).isoformat(),'python':os.sys.version,'numpy':version('numpy'),'pytest':version('pytest'),'scope':'local RTL simulation; no physical FPGA or AWS shell validation','platform':platform.platform(),'steps':{},'build_sha256':{str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in [ROOT/'Makefile',ROOT/'host/Makefile',ROOT/'requirements.lock.txt',ROOT/'.github/workflows/verify.yml']},'source_sha256':{str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for d in ['rtl','sim','host','model','scripts','tests','models'] for f in sorted((ROOT/d).rglob('*')) if f.is_file() and f.suffix in ['.sv','.cpp','.c','.h','.hpp','.py','.json'] and '__pycache__' not in str(f)}}
    def run(name,cmd,cwd,expected_exit=0):
        start=time.monotonic();p=subprocess.run(cmd,cwd=cwd,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=240)
        (logdir/(name+'.log')).write_text(p.stdout);report['steps'][name]={'exit_code':p.returncode,'seconds':round(time.monotonic()-start,3),'command':cmd,'expected_exit_code':expected_exit}
        print(name, 'PASS' if p.returncode==expected_exit else 'FAIL',flush=True)
        if p.returncode != expected_exit: print(p.stdout[-8000:]);raise RuntimeError(name)
    success=False
    try:
        report['verilator']=subprocess.check_output(['verilator','--version'],text=True).strip()
        with tempfile.TemporaryDirectory(prefix='npu1-',dir='/tmp') as tmp:
            t=Path(tmp)
            for d in ['rtl','sim','host','model','models','tests','scripts']:shutil.copytree(ROOT/d,t/d,ignore=shutil.ignore_patterns('__pycache__','*.o','test_npu'))
            (t/'artifacts').mkdir()
            files=[f'rtl/{x}.sv' for x in RTL]
            if not args.only or args.only=='lint':run('lint',['verilator','--lint-only','--assert','-Wall','--top-module','npu_axil']+files,t)
            if not args.only:run('model',[os.sys.executable,'-m','pytest','-q','tests'],t)
            for target,top in [('test-pe','tb_mac_pe'),('test-array','tb_array'),('test-core','tb_core'),('test-axil','tb_axil')]:
                if args.only and args.only!=target:continue
                run(target+'-build',['verilator','--binary','--timing','--assert','-Wall','-Wno-INITIALDLY','-Wno-UNUSEDSIGNAL','--top-module',top,'--Mdir',str(t/target),'-j','4']+files+[f'sim/{top}.sv'],t)
                run(target,[str(t/target/('V'+top))],t)
            if not args.only or args.only=='test-array':
                for rows,cols in [(1,1),(3,5),(4,4)]:
                    name=f'timing-{rows}x{cols}'
                    run(name+'-build',['verilator','--binary','--timing','--assert','-Wall','-Wno-UNUSEDSIGNAL','--top-module','tb_timing',f'-GR={rows}',f'-GC={cols}','--Mdir',str(t/name),'-j','4']+files+['sim/tb_timing.sv'],t)
                    run(name,[str(t/name/'Vtb_timing')],t)
            if not args.only or args.only=='demo':
                run('host-cli-build',['make','-C','host'],t)
                run('host-unavailable',['host/npu_validate','--aws','not-used.bin','0'],t,expected_exit=1)
                run('host-compile',['cc','-std=c11','-Wall','-Wextra','-Werror','-Ihost','-c','host/npu_runtime.c','-o',str(t/'runtime.o')],t)
                run('e2e-build',['verilator','--cc','--exe','--build','--assert','-Wall','--top-module','npu_axil','-GAXI_ADDR_WIDTH=32','--Mdir',str(t/'e2e'),'-j','4','-CFLAGS','-I'+str(t/'host'),'-LDFLAGS',str(t/'runtime.o')]+files+[str(t/'sim/host_sim.cpp')],t)
                for bus_seed, arithmetic_seed in [(1,20261029),(7,20261030),(42,20261031)]:
                    run('fixtures-'+str(arithmetic_seed),[os.sys.executable,str(ROOT/'scripts/make_fixtures.py'),str(t/'fixtures.bin'),'--seed',str(arithmetic_seed)],ROOT)
                    run('e2e-seed-'+str(bus_seed),[str(t/'e2e/Vnpu_axil'),str(t/'fixtures.bin'),str(bus_seed)],t)
                run('watchdog-build',['verilator','--cc','--exe','--build','--assert','-Wall','--top-module','npu_axil','-GAXI_ADDR_WIDTH=32','-GWATCHDOG_CYCLES=64','--Mdir',str(t/'watchdog'),'-j','4','-CFLAGS','-I'+str(t/'host'),'-LDFLAGS',str(t/'runtime.o')]+files+[str(t/'sim/watchdog_sim.cpp')],t)
                run('watchdog',[str(t/'watchdog/Vnpu_axil')],t)
            if not args.only:
                run('image-demo',[os.sys.executable,str(ROOT/'scripts/demo_smoke.py')],ROOT)
        success=True
    except (RuntimeError,subprocess.TimeoutExpired) as e:report['failure']=str(e)
    finally:
        report['passed']=success;(ROOT/'reports').mkdir(exist_ok=True)
        (ROOT/'reports'/((args.only or 'regression')+'.json')).write_text(json.dumps(report,indent=2)+'\n')
    return 0 if success else 1
if __name__=='__main__':raise SystemExit(main())
