#!/usr/bin/env python3
"""Local planning arithmetic only; never authorizes, provisions or stops AWS."""
import argparse,math
p=argparse.ArgumentParser(description=__doc__)
for name in ['hourly-rate','hours','storage-reserve','cap']:p.add_argument('--'+name,type=float,required=True)
a=p.parse_args();v=vars(a)
if any(not math.isfinite(x) or x<0 for x in v.values()) or a.cap==0:p.error('Use finite nonnegative values and a positive cap')
estimate=a.hourly_rate*a.hours*1.2+a.storage_reserve
print(f'Planning allowance with 20% compute contingency: ${estimate:.2f}; proposed cap: ${a.cap:.2f}')
print('This is not a billing cap or shutdown mechanism. Rates must be checked for the chosen region.')
raise SystemExit(0 if estimate<=a.cap else 'REFUSE: proposed plan exceeds cap')
