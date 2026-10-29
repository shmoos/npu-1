#!/usr/bin/env python3
"""Read-only hash check of a staged source package, never a hardware gate."""
import argparse,hashlib,json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('directory',type=Path);a=p.parse_args()
m=json.loads((a.directory/'npu_manifest.json').read_text());files=m['sha256']
if not files:raise SystemExit('FAIL empty manifest')
for relative,expected in files.items():
 path=(a.directory/relative).resolve()
 if not path.is_relative_to(a.directory.resolve()):raise SystemExit('FAIL unsafe manifest path')
 if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=expected:raise SystemExit('FAIL '+relative)
print('PASS',len(files),'source hashes; no AWS simulation/build/deployment claim')
