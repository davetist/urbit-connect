from targets import TARGETS
"""Run actual desk tests through the pinned base desk's -test thread."""
import argparse
import re
import sys
from pathlib import Path
from dev_ship import ROOT, rpc


def run(state, suites):
    count=0
    for suite in suites:
        if not re.fullmatch(r"[a-z-]+",suite):
            raise ValueError("invalid suite")
        output=rpc(state,"command",command=f"-test /=connect=/tests/connect/{suite}",timeout=180)["output"]
        log=ROOT/".work/alpha/logs"/f"hoon-{suite}.log"
        log.parent.mkdir(parents=True,exist_ok=True);log.write_text(output)
        tests=re.findall(r"OK\s+/[^\n]+",output)
        failed=any(s in output for s in ("FAILED", "CRASHED", "-find.", "-nest-fail", "-syntax"))
        print(output[-8000:])
        if failed or not tests:
            print(f"FAIL: {suite}: {len(tests)} passing tests; failure or zero test cases",file=sys.stderr)
            return 1
        count+=len(tests)
    print(f"PASS: {count} executed Hoon tests")
    return 0


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite",default="policy")
    parser.add_argument("--state-dir",type=Path,default=ROOT/".work/alpha/dev")
    args=parser.parse_args()
    sys.exit(run(args.state_dir,args.suite.split(',')))
