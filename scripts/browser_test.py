from targets import TARGETS
"""Run browser tests with private reports and sanitized, nonzero/no-skip counts."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
ROOT=Path(__file__).resolve().parents[1]
def main():
    TARGETS.require_owned()
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--spec',help='Comma-separated test filenames');args=parser.parse_args()
    specs=args.spec.split(',')if args.spec else[]
    if any('/'in name or not name.endswith('.spec.ts')for name in specs):raise ValueError('Use test filenames')
    directory=ROOT/'.work/alpha/browser-tests';directory.mkdir(parents=True,exist_ok=True,mode=0o700)
    identity=time.strftime('%Y%m%d-%H%M%S');report=directory/(identity+'.json');log=directory/(identity+'.log')
    command=[str(ROOT/'web/node_modules/.bin/playwright'),'test',*specs,'--reporter=json']
    environment=dict(os.environ);environment['NODE_EXTRA_CA_CERTS']=str(ROOT/'.work/alpha/tls/ca.crt')
    print('Running browser tests:',','.join(specs)or'all',flush=True)
    with report.open('w')as output,log.open('w')as errors:
        report.chmod(0o600);log.chmod(0o600)
        result=subprocess.run(command,cwd=ROOT/'web',stdout=output,stderr=errors,env=environment)
    value=json.loads(report.read_text());stats=value['stats'];safe={name:stats.get(name,0)for name in ['expected','unexpected','skipped','flaky']}
    print(json.dumps(safe,indent=2));print('Private browser report:',report)
    return 0 if result.returncode==0 and safe['expected']>0 and not any(safe[k]for k in ['unexpected','skipped','flaky'])and not value.get('errors')else 1
if __name__=='__main__':sys.exit(main())
