#!/usr/bin/env python3
"""Transform a pinned official F2 example; never create cloud resources."""
import argparse, hashlib, json, re, shutil, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
NAMES=['npu_pkg','mac_pe','skew_feeder','systolic_array_4x4','operand_buffer','tile_controller','postprocess','result_buffer','npu_core','npu_axil']
EXAMPLE='hdk/cl/examples/cl_demo/cl_axil_reg_access'
def stage(repo:Path,out:Path,check_git=True):
 lock=json.loads((ROOT/'aws/devkit.lock.json').read_text())
 if check_git:
  actual=subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip()
  if actual!=lock['commit']:raise ValueError('HDK commit differs from aws/devkit.lock.json')
 if out.name != 'cl_axil_reg_access':raise ValueError('Official build requires output basename cl_axil_reg_access')
 if out.exists():raise ValueError('Output already exists; choose a new empty staging path')
 template=repo/EXAMPLE
 for relative,expected in lock['template_sha256'].items():
  if hashlib.sha256((template/relative).read_bytes()).hexdigest()!=expected:raise ValueError('Modified HDK template: '+relative)
 shutil.copytree(template,out,symlinks=False)
 design=out/'design';top=design/'cl_axil_reg_access.sv';s=top.read_text()
 pre=s[:s.index('  // FSM states')]
 pre=re.sub(r'(logic[^;\n]+?)\s*=\s*[^;\n]+;', r'\1;', pre)
 # Keep the official top-level ports, PCI IDs, unused interfaces, and OCL slice.
 block=s[s.index('// OCL register slice'):s.index('//-------------------------------------------------\n// AXI-lite Handshake')]
 debug=s[s.index('`ifndef SIMULATION\ncl_debug_bridge'):s.index('`ifndef NO_CL_AXIL_DEBUG_ILA')]
 reset='''  (* ASYNC_REG = "TRUE" *) logic [1:0] npu_reset_sync;
  always_ff @(posedge clk_main_a0 or negedge rst_main_n)
    if(!rst_main_n) npu_reset_sync <= 0;
    else npu_reset_sync <= {npu_reset_sync[0],1'b1};
  wire npu_rst_n = npu_reset_sync[1];
'''
 block=block.replace('(rst_main_n)', '(npu_rst_n)')
 top.write_text(pre+reset+block+'\n`include "npu_instance.svh"\n'+debug+'\nendmodule\n')
 for name in NAMES:shutil.copy2(ROOT/f'rtl/{name}.sv',design)
 shutil.copy2(ROOT/'aws/cl_npu/design/npu_instance.svh',design)
 shutil.copy2(ROOT/'aws/cl_npu/verif/tests/test_npu.sv',out/'verif/tests')
 enc=out/'build/scripts/encrypt.tcl';s=enc.read_text();marker='#---- End of section replaced by Developer ---'
 assert marker in s
 s=s.replace(marker,'\n'.join('file copy -force $CL_DIR/design/'+name+'.sv $src_post_enc_dir' for name in NAMES)+'\nfile copy -force $CL_DIR/design/npu_instance.svh $src_post_enc_dir\n'+marker)
 # Include .svh in encryption too.
 s=s.replace('*.{v,sv,vh,inc}','*.{v,sv,svh,vh,inc}');enc.write_text(s)
 synth=out/'build/scripts/synth_cl_axil_reg_access.tcl';s=synth.read_text();old='read_verilog -sv [glob ${src_post_enc_dir}/*.{s,}v]';assert old in s
 s=s.replace(old,'read_verilog -sv [list '+ ' '.join('${src_post_enc_dir}/'+name+'.sv' for name in NAMES+['cl_axil_reg_access'])+']')
 # No ILA instantiated in this small design.
 s=s.replace('read_ip ${HDK_IP_SRC_DIR}/ila_axil/ila_axil.xci','');synth.write_text(s)
 for sim in ['xsim','vcs','questa']:
  file=out/f'verif/scripts/top.{sim}.f';s=file.read_text();marker='$CL_DIR/design/cl_axil_reg_access.sv';assert marker in s
  s=s.replace(marker,'\n'.join('$CL_DIR/design/'+name+'.sv' for name in NAMES)+'\n'+marker)
  s=s.replace('$CL_DIR/verif/tests/cl_axil_fsm_coverage.sv','');file.write_text(s)
 with (out/'build/constraints/cl_timing_user.xdc').open('a') as f:f.write('\n'+(ROOT/'aws/constraints/npu_user.xdc').read_text())
 manifest={'hdk_commit':lock['commit'],'top_module':'cl_axil_reg_access','status':'staged only; requires actual HDK simulation and Vivado implementation','sha256':{str(p.relative_to(out)):hashlib.sha256(p.read_bytes()).hexdigest() for p in out.rglob('*') if p.is_file()}}
 (out/'npu_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 return manifest
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--aws-dir',required=True,type=Path);ap.add_argument('--output',required=True,type=Path);a=ap.parse_args()
 m=stage(a.aws_dir.resolve(),a.output.resolve());print('Staged',len(m['sha256']),'files. HDK simulation/build not yet verified.')
