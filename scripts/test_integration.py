"""Run required live HTTPS integration suites; zero/skipped tests are failures."""
import argparse
from pathlib import Path
import re
import sys
import unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests/integration'))
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--suite',default='info,auth,documents,sync,owner,limits,lifecycle,recovery,entrypoints,alpha_reliability');args=parser.parse_args()
    suites=args.suite.split(',')
    if any(not re.fullmatch('[a-z_]+',s)for s in suites):raise ValueError('Invalid suite name')
    tests=unittest.TestSuite(unittest.defaultTestLoader.loadTestsFromName('test_'+s)for s in suites)
    result=unittest.TextTestRunner(verbosity=2).run(tests)
    return 0 if result.wasSuccessful()and result.testsRun>0 and not result.skipped else 1
if __name__=='__main__':sys.exit(main())
