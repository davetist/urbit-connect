"""Materialize identical JSON boundary fixtures for Hoon and Swift; --check detects drift."""
import argparse
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def generated():
    source=ROOT/'protocol/v1/fixtures/json-boundaries.json'
    parts=[':: Generated from protocol/v1/fixtures/json-boundaries.json; regenerate with scripts/protocol_fixtures.py.','/+  *test, cj=connect-json','|%']
    for fixture in json.loads(source.read_text()):
        raw=fixture['input'].replace('\\','\\\\').replace("'","\\'").replace('\n','\\0a')
        truth='&'if fixture['valid']else'|'
        parts += ['++  test-fixture-'+fixture['name'],f"  (expect-eq !>({truth}) !>(?=(^ (parse:cj '{raw}'))))"]
    parts+=['--']
    return {ROOT/'desk/tests/connect/fixtures.hoon':'\n'.join(parts)+'\n',ROOT/'sdk/swift/Tests/UrbitConnectTests/Fixtures/json-boundaries.json':source.read_text()}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');args=parser.parse_args()
    for path,content in generated().items():
        if args.check:
            if not path.exists()or path.read_text()!=content:raise SystemExit(f'Fixture drift: {path.relative_to(ROOT)}')
        else:path.parent.mkdir(parents=True,exist_ok=True);path.write_text(content)
    print('Shared fixtures verified'if args.check else'Shared fixtures generated')
