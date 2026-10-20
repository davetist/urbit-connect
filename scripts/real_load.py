"""Measure real connect-dev HTTPS/packet profiles and bounded server resources.

Owner/scoped credentials remain on the selected test host. Counts and timing/resource aggregates
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
    raise SystemExit('This quota qualification workload is retired. Historical sources and results are preserved; no workload was started.')


if __name__ == '__main__': run()
