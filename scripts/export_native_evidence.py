from targets import TARGETS
"""Copy only explicitly named product screenshots from a private, passing XCTest result."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
from dev_ship import ROOT

NAMES = [
    'Personal-Buy-milk-saved', 'owner-edit-visible-native', 'offline-durable-draft',
    'conflict-both-versions', 'conflict-actions', 'unsupported-data-preserved',
    'long-task-text',
    'large-type-dark-lists', 'revoked-native',
]
REAL_NAMES = ['real-ship-saved','real-ship-desk-update-catch-up','real-ship-conflict','real-ship-revoked']

def export(result, small=False,real=False):
    result = result.resolve()
    result.relative_to((ROOT / '.work/alpha/native-tests').resolve())
    report = json.loads(subprocess.check_output([
        'xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(result)
    ], text=True))
    if report.get('failedTests') or report.get('skippedTests') or not report.get('passedTests'):
        raise RuntimeError('Evidence requires a passing result with no skipped tests')
    private = result.with_name(result.stem + '-attachments')
    private.mkdir(mode=0o700, exist_ok=True)
    subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result),
                    '--output-path', str(private)], check=True, capture_output=True)
    manifest = json.loads((private / 'manifest.json').read_text())
    target = ROOT / 'artifacts/alpha/native' / ('real' if real else 'small' if small else 'large')
    target.mkdir(parents=True, exist_ok=True)
    names=REAL_NAMES if real else NAMES
    for name in names:
        matches = [a for test in manifest for a in test['attachments']
                   if a.get('suggestedHumanReadableName', '').startswith(name + '_')
                   and a.get('exportedFileName', '').endswith('.png')]
        if len(matches) != 1:
            raise RuntimeError('Expected exactly one named screenshot: ' + name)
        source = private / matches[0]['exportedFileName']
        source.resolve().relative_to(private.resolve())
        shutil.copyfile(source, target / (name + '.png'))
    (target / 'provenance.json').write_text(json.dumps({
        'privateResult': result.name, 'screenshots': names,
        'deviceClass': 'iPhone SE (3rd generation)' if small else 'iPhone 17 Pro',
        'visualInspection': 'required separately',
    }, indent=2) + '\n')
    print('Exported', len(names), 'named product screenshots to', target)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('result', type=Path)
    parser.add_argument('--small', action='store_true')
    args = parser.parse_args()
    export(args.result, args.small)
