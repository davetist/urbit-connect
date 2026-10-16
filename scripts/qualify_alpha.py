"""Summarize recorded Connect observations; never run tests or issue readiness verdicts."""
import argparse
import hashlib
import json
from pathlib import Path
import release_check

ROOT = release_check.ROOT


def identity(manifest):
    return hashlib.sha256(json.dumps({key: manifest[key] for key in ['version', 'source', 'artifacts', 'toolchain']}, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def evaluate(manifest, checks, manual):
    rows = checks.get('checks', [])
    return {
        'reportKind': 'observations',
        'releaseIdentity': identity(manifest),
        'recordedScope': checks.get('scope', []),
        'recordedAt': checks.get('recordedAt'),
        'recordedSourcesMatch': checks.get('source') == manifest.get('source'),
        'automatedObservations': rows,
        'manualObservations': manual,
        'publicationBlockers': manifest.get('publicationBlockers', []),
        'note': 'Recorded outcomes retain their original scope and date. Missing observations, source differences, elapsed time and participant counts do not decide readiness. This report runs no checks and certifies no current behavior.',
    }


def read_observations(path):
    return json.loads(path.read_text()) if path.is_file() else {}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release-manifest', required=True, type=Path)
    parser.add_argument('--checks', type=Path, default=ROOT / 'artifacts/alpha/checks.json')
    parser.add_argument('--manual-evidence', type=Path, default=ROOT / 'artifacts/alpha/manual-evidence.json')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    manifest = json.loads(args.release_manifest.read_text())
    # This checks artifact/source integrity, not whether old evidence qualifies use.
    release_check.verify_manifest(manifest)
    result = evaluate(manifest, read_observations(args.checks), read_observations(args.manual_evidence))
    result['observationFiles'] = {str(path): release_check.digest(path) for path in [args.checks, args.manual_evidence] if path.is_file()}
    rendered = json.dumps(result, indent=2) + '\n'
    if args.output:
        args.output.write_text(rendered)
    print(rendered, end='')


if __name__ == '__main__':
    main()
