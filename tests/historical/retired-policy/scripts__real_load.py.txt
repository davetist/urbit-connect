"""Measure real connect-dev HTTPS/packet profiles and bounded server resources.

Owner/scoped credentials remain on reference-host. Counts and timing/resource aggregates
are saved locally on that host; SDK cache-install timing is separate evidence.
"""
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time
import urllib.request
from real_reference import Reference, ROOT, CLIENT, REDIRECT, operation, mutation, distribution, private_json
from netem_host import control

PROC = Path('/proc')


def resource(api):
    # Resolve the runtime by its exact authorized pier argument, never a guessed PID.
    candidates = set()
    for path in PROC.glob('[0-9]*/cmdline'):
        try:
            args = path.read_bytes().split(b'\0')
            if api.target['pier'].encode() in args: candidates.add(int(path.parent.name))
        except (FileNotFoundError, PermissionError): pass
    rows = []
    for path in PROC.glob('[0-9]*/status'):
        try:
            values = dict(line.split(':', 1) for line in path.read_text().splitlines() if ':' in line)
            rows.append((int(path.parent.name), int(values['PPid']), values))
        except (FileNotFoundError, PermissionError): pass
    parents = {pid for pid, parent, _ in rows if pid in candidates and parent not in candidates}
    assert len(parents) == 1, 'Exact runtime process did not resolve uniquely'
    owned = set(parents)
    while True:
        children = owned | {pid for pid, parent, _ in rows if parent in owned}
        if children == owned: break
        owned = children
    pier = Path(api.target['pier']); log = pier / '.urb/log'
    files = [p for p in log.rglob('*') if p.is_file()]
    processes = []
    totals = {field: 0 for field in ['VmRSS', 'RssAnon', 'RssFile', 'RssShmem', 'VmSwap']}
    for pid, parent, values in rows:
        if pid not in owned: continue
        assert 'VmRSS' in values, 'Runtime RSS is unavailable'
        stat = (PROC / str(pid) / 'stat').read_text().rsplit(')', 1)[1].split()
        processes.append({'pid': pid, 'parent': parent, 'startTicks': int(stat[19])})
        for field in totals: totals[field] += int(values.get(field, '0 kB').split()[0]) * 1024
    assert totals['VmRSS'] > 0, 'Runtime RSS is unavailable'
    return {'runtimeRSSBytes': totals['VmRSS'], 'runtimeAnonymousRSSBytes': totals['RssAnon'],
            'runtimeFileRSSBytes': totals['RssFile'], 'runtimeSharedRSSBytes': totals['RssShmem'],
            'runtimeSwapBytes': totals['VmSwap'], 'runtimeProcessCount': len(owned),
            'runtimeIdentity': {'bootId': (PROC / 'sys/kernel/random/boot_id').read_text().strip(),
                                'processes': sorted(processes, key=lambda row: row['pid'])},
            'allocatedPierBytes': int(subprocess.check_output(['du', '-sk', str(pier)], text=True).split()[0]) * 1024,
            'allocatedEventLogBytes': int(subprocess.check_output(['du', '-sk', str(log)], text=True).split()[0]) * 1024,
            'eventDatabaseFileBytes': sum(p.stat().st_size for p in files if p.name == 'data.mdb'),
            'freeHostBytes': os.statvfs(pier).f_bavail * os.statvfs(pier).f_frsize}


def fill(api, token, count=1000):
    ids = []
    for start in range(0, count, 32):
        ops = [operation({'check': 'small reference document', 'completed': False}) for _ in range(min(32, count - start))]
        ids.extend(op['id'] for op in ops)
        assert api.request('/connect/v1/mutations', 'POST', mutation(*ops), token=token)[0] == 200
    return ids


def snapshot(api, token):
    start = time.monotonic(); status, page = api.request('/connect/v1/snapshots', 'POST', {}, token=token); assert status == 200
    rows = []; cursor = page['atCursor']
    while True:
        rows.extend(page['documents']); assert page['atCursor'] == cursor
        if page['nextPage'] is None: break
        status, page = api.request('/connect/v1/snapshots/' + page['snapshotId'] + '?page=' + page['nextPage'], token=token); assert status == 200
    return rows, cursor, time.monotonic() - start


def run():
    assert (ROOT / 'reference-update.json').is_file(), 'Real baseline/update preservation must pass first'
    api = Reference(); space = api.register()['namespace']; api.erase(space); token = api.connect()['access_token']
    ids = fill(api, token)
    assert api.request('/connect/v1/mutations', 'POST', mutation(operation({'check': '1001st document'})), token=token)[0] == 429
    warm = resource(api); measurements = []
    try:
        for profile in ['local', '100ms-1percent']:
            control({'action': 'profile', 'profile': profile})
            grant = api.connect(); token = grant['access_token']; reads = []; writes = []
            for id in ids[:20]:
                start = time.monotonic(); status, row = api.request('/connect/v1/collections/notes/documents/' + id, token=token); assert status == 200; reads.append(time.monotonic() - start)
                start = time.monotonic(); status, _ = api.request('/connect/v1/mutations', 'POST', mutation(operation({'check': 'updated reference document'}, id, row['revision'])), token=token); assert status == 200; writes.append(time.monotonic() - start)
            rows, cursor, seconds = snapshot(api, token); assert len(rows) == 1000 and len({row['id'] for row in rows}) == 1000
            stats = control({'action': 'status'})
            measurements.append({'profile': profile, 'read': distribution(reads), 'write': distribution(writes), 'snapshotDownloadSeconds': round(seconds, 3), 'documents': len(rows), 'qdisc': stats['qdisc']})
            assert api.request('/connect/owner/v1/revoke', 'POST', {'sessionId': grant['grant']['sessionId']}, owner=True)[0] == 200
        control({'action': 'profile', 'profile': 'local'})
        grant = api.connect(); token = grant['access_token']; bodies = []
        for id in ids[:10]:
            status, row = api.request('/connect/v1/collections/notes/documents/' + id, token=token); assert status == 200
            bodies.append(json.dumps(mutation(operation({'check': 'eventual recovery after loss'}, id, row['revision'])), separators=(',', ':')).encode())
        _, before_cursor, _ = snapshot(api, token)
        control({'action': 'profile', 'profile': '500ms-5percent'}); received = []
        for body in bodies:
            try: received.append(api.request('/connect/v1/mutations', 'POST', body, token=token))
            except RuntimeError: received.append(None)
        severe_stats = control({'action': 'status'})
        control({'action': 'profile', 'profile': 'local'})
        for body, original in zip(bodies, received):
            status, replay = api.request('/connect/v1/mutations', 'POST', body, token=token); assert status == 200
            if original is not None and original[0] == 200: assert replay == original[1]
        _, after_cursor, _ = snapshot(api, token)
        assert int(after_cursor.split(':')[-1]) - int(before_cursor.split(':')[-1]) == len(bodies)
        measurements.append({'profile': '500ms-5percent', 'heldExactRequests': len(bodies), 'effectsAfterRecovery': len(bodies), 'successfulRepliesBeforeRecovery': sum(row is not None and row[0] == 200 for row in received), 'eventualProgressAfterRecovery': True, 'qdisc': severe_stats['qdisc']})
        # Exact 4 MiB payload boundary, separately from the small-doc latency sample.
        api.erase(space); token = api.connect()['access_token']
        for _ in range(32):
            assert api.request('/connect/v1/mutations', 'POST', mutation(*[operation({'x': 'a' * (16384 - 8)}) for _ in range(8)]), token=token)[0] == 200
        assert api.request('/connect/v1/mutations', 'POST', mutation(operation({'x': 'a'})), token=token)[0] == 429
        payload_quota = {'liveJSONPayloadBytes': 4 * 1024 * 1024, 'documents': 256, 'nextWriteRejected': True}
        api.erase(space)
        after = resource(api)
        report = {'passed': True, 'realShip': True, 'normalSystemTLS': True, 'kernelRuntime': 'Vere 4.6 / Zuse 408', 'hardware': Path('/proc/device-tree/model').read_text().rstrip('\0'), 'os': platform.platform(), 'memoryBytes': int(next(line.split()[1] for line in Path('/proc/meminfo').read_text().splitlines() if line.startswith('MemTotal:'))) * 1024, 'networkScope': 'tc netem on relay-to-private-Eyre TCP egress inside an unprivileged namespace; host interfaces unchanged', 'measurements': measurements, 'payloadQuota': payload_quota, 'warm': warm, 'afterCleanup': after, 'snapshotMeasurement': 'Actual HTTPS download only; native SDK SQLite installation is separate', 'soakComplete': False}
        private_json('reference-load.json', report)
        threshold_ok = all(row['read']['p95Ms'] < (1000 if row['profile'] == 'local' else 2000) and row['write']['p95Ms'] < (1000 if row['profile'] == 'local' else 2000) and row['snapshotDownloadSeconds'] < 30 for row in measurements if 'read' in row)
        report['passed'] = threshold_ok; private_json('reference-load.json', report)
        print(json.dumps({'realHostLoadPassed': threshold_ok, 'profileMeasurements': [{key: row[key] for key in ['profile', 'read', 'write', 'snapshotDownloadSeconds'] if key in row} for row in measurements], 'quota4MiB': True, 'effectsAfterLoss': len(bodies)}))
        assert threshold_ok, 'Reference latency threshold failed; aggregate retained'
    finally: control({'action': 'profile', 'profile': 'local'})


if __name__ == '__main__': run()
