"""Read-only HTTPS/protocol preflight. Never install, authenticate as owner or relax TLS."""
import argparse
import json
import os
from pathlib import Path
import shutil
import ssl
import urllib.error
import urllib.parse
import urllib.request
from targets import ROOT, TARGETS


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def origin(value):
    parsed = urllib.parse.urlsplit(value)
    try:
        port = parsed.port
    except ValueError as error:
        raise ValueError('Use an HTTPS base address with a valid port') from error
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username is not None or parsed.password is not None or parsed.path not in ('', '/') or parsed.query or parsed.fragment or port == 0:
        raise ValueError('Use the exact HTTPS base address, without paths or credentials')
    return urllib.parse.urlunsplit(('https', parsed.netloc.lower(), '', '', ''))


def inspect_info(value, expected_instance=None, expected_ship=None):
    if not isinstance(value, dict) or type(value.get('protocolVersion')) is not int or value['protocolVersion'] != 1:
        raise ValueError('Unsupported Connect protocol')
    if value.get('configured') is not True:
        raise ValueError('Connect is installed but the HTTPS issuer is not configured')
    if not isinstance(value.get('instanceId'), str) or not 0 < len(value['instanceId'].encode()) <= 128:
        raise ValueError('Invalid ship instance identity')
    if expected_instance and value['instanceId'] != expected_instance:
        raise ValueError('The ship instance differs from the selected target')
    if expected_ship and value.get('ship') != expected_ship:
        raise ValueError('The asserted ship differs from the selected target')
    epoch = value.get('syncEpoch')
    if not isinstance(epoch, str) or not epoch.isascii() or not epoch.isdecimal() or not 0 < len(epoch) <= 128 or epoch.startswith('0'):
        raise ValueError('Invalid restore generation')
    return {'protocolVersion': 1, 'configured': True, 'development': value.get('development') is True, 'instanceMatches': expected_instance is None or value['instanceId'] == expected_instance, 'assertedShipMatches': expected_ship is None or value.get('ship') == expected_ship}


def doctor(address, *, fixture=False, expected_instance=None, expected_ship=None):
    address = origin(address)
    if fixture:
        TARGETS.require_owned()
        if address != TARGETS.origin():
            raise ValueError('Development trust is restricted to the owned alpha origin')
    context = ssl.create_default_context(cafile=TARGETS.work / 'tls/ca.crt' if fixture else None)
    opener = urllib.request.build_opener(NoRedirect(), urllib.request.HTTPSHandler(context=context))
    try:
        with opener.open(address + '/connect/v1/info', timeout=15) as response:
            if response.status != 200 or response.headers.get_content_type() != 'application/json':
                raise ValueError('The endpoint is not a Connect JSON service')
            raw = response.read(65537)
            if len(raw) > 65536:
                raise ValueError('Oversized preflight response')
            value = json.loads(raw)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            raise ValueError('Connect desk is missing at this origin') from error
        if 300 <= error.code < 400:
            raise ValueError('Preflight refused an endpoint redirect') from error
        raise ValueError(f'Connect service returned HTTP {error.code}') from error
    except urllib.error.URLError as error:
        if isinstance(error.reason, ssl.SSLCertVerificationError):
            raise ValueError('The HTTPS certificate is not valid and trusted') from error
        raise ValueError('The HTTPS endpoint is unreachable') from error
    if value.get('issuer') != address + '/connect':
        raise ValueError('The issuer differs from the requested origin')
    report = inspect_info(value, expected_instance, expected_ship)
    report['localBuildFreeBytes'] = shutil.disk_usage(ROOT).free
    report['hostSpaceVerified'] = False
    return report


def write_report(path, value):
    allowed = {'protocolVersion', 'configured', 'development', 'instanceMatches',
               'assertedShipMatches', 'localBuildFreeBytes', 'hostSpaceVerified'}
    report = {key: value[key] for key in allowed if key in value}
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w') as stream:
        stream.write(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('origin')
    parser.add_argument('--fixture', action='store_true')
    parser.add_argument('--expected-instance')
    parser.add_argument('--expected-ship')
    parser.add_argument('--output', type=Path, help='Create a private diagnostic JSON file; refuses overwrite')
    args = parser.parse_args()
    try:
        report = doctor(args.origin, fixture=args.fixture, expected_instance=args.expected_instance, expected_ship=args.expected_ship)
        if args.output: write_report(args.output, report)
        print(json.dumps(report, indent=2))
    except (ValueError, json.JSONDecodeError):
        # Deliberately exclude raw responses, headers, tokens and document data.
        raise SystemExit('Preflight failed; check the HTTPS address, certificate, Connect configuration and selected target.')


if __name__ == '__main__':
    main()
