"""Qualify the private alpha; missing technical or human/elapsed evidence fails closed."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from targets import ROOT, TARGETS, Targets
import release_check

AUTOMATED = {'tooling', 'protocol-schema', 'web-typecheck', 'web-codec', 'web-layout', 'web-build', 'web-bundle', 'desk-stage', 'hoon', 'integration', 'browser-owner', 'browser-eauth', 'browser-expiry', 'sdk', 'sdk-public-consumer', 'ios', 'ios-small', 'reload-retry', 'restore-files', 'load', 'package'}
COUNTED = {'tooling', 'protocol-schema', 'web-codec', 'web-layout', 'hoon', 'integration', 'browser-owner', 'browser-eauth', 'browser-expiry', 'sdk', 'sdk-public-consumer', 'ios', 'ios-small'}
PUBLICATION_ONLY = {'sourceOwner', 'maintenanceContact', 'securityContact', 'publication authorization'}
MANUAL = {
    'simulator-visual-accessibility': {},
    'preserved-install-app-update': {},
    'restore-operators': {'operators': 2, 'rehearsals': 2},
    'independent-sdk-integration': {'independent': True},
    'real-arm64-install-update': {'independent': True},
    'real-host-latency-loss-capacity': {},
    'real-host-soak': {'durationSeconds': 6 * 3600},
    'independent-auth-storage-review': {'independent': True},
    'practical-trial': {'durationSeconds': 7 * 86400, 'testers': 2},
}


def identity(manifest):
    return hashlib.sha256(json.dumps({key: manifest[key] for key in ['version', 'source', 'artifacts', 'toolchain']}, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def evaluate(manifest, checks, manual):
    failures = []
    rows = checks.get('checks', [])
    by_name = {row.get('check'): row for row in rows}
    if checks.get('source') != manifest.get('source'):
        failures.append('Automated results do not match the release sources')
    if 'all' not in checks.get('scope', []) and set(checks.get('scope', [])) != {'environment', 'protocol', 'web-build', 'hoon', 'integration', 'web', 'sdk', 'ios', 'ios-small', 'reliability', 'load', 'package', 'evidence'}:
        failures.append('Full final automated scope has not executed')
    for name in sorted(AUTOMATED):
        row = by_name.get(name)
        if not row or row.get('passed') is not True:
            failures.append('Automated check missing or failed: ' + name)
        elif name in COUNTED and (type(row.get('cases')) is not int or row['cases'] <= 0):
            failures.append('Required cases are zero/missing: ' + name)
        elif row.get('skipped', 0):
            failures.append('Required cases were skipped: ' + name)
    bound = identity(manifest)
    for name, requirements in MANUAL.items():
        row = manual.get(name, {})
        if row.get('status') != 'passed' or row.get('releaseIdentity') != bound or not row.get('evidence') or not row.get('performedBy'):
            failures.append('Required evidence pending: ' + name); continue
        for field, expected in requirements.items():
            actual = row.get(field)
            if isinstance(expected, bool):
                valid = actual is expected
            else:
                valid = type(actual) in (int, float) and actual >= expected
            if not valid:
                failures.append('Required evidence below gate: ' + name + '/' + field)
        for reference in row['evidence']:
            path = ROOT / reference
            if not path.resolve().is_relative_to((ROOT / 'artifacts/alpha').resolve()) or not path.is_file():
                failures.append('Evidence file unavailable: ' + name)
    publication = manifest.get('publicationBlockers', [])
    failures.extend('Release prerequisite pending: ' + name for name in publication if name not in PUBLICATION_ONLY)
    return {'releaseIdentity': bound, 'qualificationScope': 'private-alpha', 'qualified': not failures,
            'failures': failures, 'automatedCases': sum(row.get('cases') or 0 for row in rows),
            'publicationBlockers': publication}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release-manifest', required=True, type=Path)
    parser.add_argument('--targets', required=True, type=Path)
    parser.add_argument('--manual-evidence', type=Path, default=ROOT / 'artifacts/alpha/manual-evidence.json')
    parser.add_argument('--all', action='store_true')
    args = parser.parse_args()
    Targets(ROOT, manifest=args.targets).require_owned()
    manifest = json.loads(args.release_manifest.read_text())
    release_check.verify_manifest(manifest)
    if args.all:
        subprocess.run([sys.executable, ROOT / 'scripts/check.py', '--all'], cwd=ROOT, check=True)
        # Rebuilds must leave the source and unsigned artifact identities unchanged.
        current = release_check.manifest(manifest['artifacts'])
        if identity(current) != identity(manifest):
            raise ValueError('Sources/artifacts changed during qualification')
    checks = json.loads((ROOT / 'artifacts/alpha/checks.json').read_text())
    manual = json.loads(args.manual_evidence.read_text()) if args.manual_evidence.is_file() else {}
    result = evaluate(manifest, checks, manual)
    result['checksSHA256'] = release_check.digest(ROOT / 'artifacts/alpha/checks.json')
    result['targetsSHA256'] = release_check.digest(args.targets)
    output = ROOT / 'artifacts/alpha/qualification.json'; output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    if not result['qualified']:
        raise SystemExit(2)


if __name__ == '__main__':
    main()
