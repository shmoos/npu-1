#!/usr/bin/env python3
import argparse, json, struct, sys
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from model.gemm_ref import postprocess_ref
from model.inference_ref import IntegerInferenceEngine
parser=argparse.ArgumentParser()
parser.add_argument('output')
parser.add_argument('--seed',type=int,default=20261029)
args=parser.parse_args()
rng=np.random.default_rng(args.seed)
with open(args.output,'wb') as f:
 def words(*xs):f.write(struct.pack('<'+'I'*len(xs),*xs))
 def data(x,dtype):f.write(np.asarray(x,dtype=dtype).tobytes())
 cases=160;words(0x4e505531,cases)
 for i in range(cases):
  m=1+i%9;n=1+(i*7)%13;k=[1,2,3,4,7,16,31,64,255,1023,1024][i%11];mode=i%3
  mult=[1,3,0x7fffffff,1234567][i%4];shift=[0,1,8,31,62][i%5]
  a=rng.integers(-128,128,(m,k),dtype=np.int8);b=rng.integers(-128,128,(k,n),dtype=np.int8)
  if i%11==0:a[:]=-128;b[:]=-128
  bias=rng.integers(-2**31,2**31,n,dtype=np.int32) if i%7==0 else rng.integers(-10000,10000,n,dtype=np.int32)
  raw=a.astype(np.int64)@b.astype(np.int64);c=np.zeros((m,n),dtype=np.int32);y=np.zeros((m,n),dtype=np.int8)
  for r in range(m):
   for col in range(n):c[r,col],y[r,col]=postprocess_ref(int(raw[r,col]),int(bias[col]),mode,mult,shift)
  words(m,n,k,mode,mult,shift);data(a,'i1');data(b,'i1');data(bias,'<i4');data(c,'<i4');data(y,'i1')
 engine=IntegerInferenceEngine('models/digits/quantized_model.json');v=json.load(open('models/digits/test_vectors.json'))

 data(engine.w1,'i1');data(engine.b1,'<i4');words(engine.requant_mult_1,engine.requant_shift_1);data(engine.w2,'i1');data(engine.b2,'<i4')
 x=engine.quantize_input(np.asarray(v['test_inputs_norm']));labels=np.asarray(v['test_labels'],dtype=np.uint8)
 _,t=engine.run_direct(x);words(len(x));data(x,'i1');data(t['hidden_i8'],'i1');data(t['logits_i32'],'<i4');data(labels,'u1')
 print('Generated',cases,'random cases and',len(x),'digits samples; arithmetic seed',args.seed)
