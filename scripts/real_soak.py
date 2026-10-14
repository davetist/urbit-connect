"""Finite 6-hour connect-dev churn/idle qualification; credentials stay remote.

Run once in the guarded reference experiment. No restart or duration below 6 actual hours
counts as passed. Only the scalar report may be exported, never soak-state.json.
"""
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import signal
import time
import traceback
import uuid
from real_reference import Reference, ROOT, operation, mutation
from real_load import resource

DURATION = 6 * 3600
PERIOD = 120
MEMORY_MEASUREMENT = 'vere-mass-sweep-resident-v1'


def private_save(path, value):
    temporary = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        stream.write(json.dumps(value, indent=2) + '\n'); stream.flush(); os.fsync(stream.fileno())
    os.replace(temporary, path)
    fd = os.open(path.parent, os.O_RDONLY)
    try: os.fsync(fd)
    finally: os.close(fd)


def exact_write(api, token, value):
    raw = json.dumps(value, separators=(',', ':')).encode()
    for attempt in range(3):
        try: status, result = api.request('/connect/v1/mutations', 'POST', raw, token=token)
        except RuntimeError:
            if attempt == 2: raise
            continue
        assert status == 200, 'Soak mutation was not acknowledged'
        break
    status, replay = api.request('/connect/v1/mutations', 'POST', raw, token=token)
    assert status == 200 and replay == result, 'Exact retry did not preserve its receipt'
    return result


def churn(api, token, space, cycle):
    assert api.documents(space) == [], 'Previously cleaned records reappeared'
    ops = [operation({'cycle': cycle, 'slot': slot, 'payload': 'x' * (128 if slot % 2 else 4096)}) for slot in range(4)]
    created = exact_write(api, token, mutation(*ops))
    rows = api.documents(space)
    expected = {op['id']: op['data'] for op in ops}
    assert {row['id']: row['data'] for row in rows} == expected and len(rows) == 4, 'Acknowledged records lost or duplicated'
    updated = exact_write(api, token, mutation(*[operation(row['data'] | {'updated': True}, row['id'], row['revision']) for row in rows]))
    rows = api.documents(space)
    assert {row['id']: row['data'] for row in rows} == {key: data | {'updated': True} for key, data in expected.items()} and len(rows) == 4, 'Acknowledged update diverged'
    deleted = exact_write(api, token, mutation(*[{'type': 'delete', 'collection': 'notes', 'id': row['id'], 'expectedRevision': row['revision']} for row in rows]))
    assert api.documents(space) == [], 'Acknowledged deletion diverged'
    assert int(updated['revision']) == int(created['revision']) + 1 and int(deleted['revision']) == int(created['revision']) + 2, 'Duplicate mutation effect'
    return {'documentsCreated': 4, 'mutationEffects': 3, 'exactReceiptReplays': 3}


def _harbor(api, route, body=None):
    connection = http.client.HTTPConnection('127.0.0.1', 18789, timeout=5)
    path = '/api/v1/ships/' + api.target['harborShipId'] + ('/' + route if route else '')
    try:
        connection.request('POST' if body is not None else 'GET', path,
                           json.dumps(body).encode() if body is not None else None,
                           {'Content-Type': 'application/json'} if body is not None else {})
        response = connection.getresponse()
        assert response.status == (204 if body is not None else 200), 'Target memory control unavailable'
        raw = response.read(8 * 1024 * 1024 + 1)
        assert len(raw) <= 8 * 1024 * 1024, 'Target terminal report exceeded its bound'
        return json.loads(raw) if raw else None
    finally: connection.close()


def _checkpoint(api):
    path = Path(api.target['pier']) / '.urb/chk/image.bin'
    assert path.is_file() and not path.is_symlink(), 'Runtime checkpoint is unavailable'
    stat = path.stat()
    return stat.st_ino, stat.st_size, stat.st_mtime_ns


def cleanup_resource(api):
    # Vere snapshots remap demand-paged loom pages. Idle RSS can consequently
    # change several-fold with unchanged live state. At BOTH boundaries, walk
    # and sweep the heap using |mass, then sample its resident pages immediately.
    # Never reset caches, compact, erase, or restart to make the gate pass.
    target = api.target
    assert target['project'] == '/absolute/project'
    assert target['pier'] == '/mnt/harbor/piers/connect-dev'
    assert re.fullmatch('[0-9a-f]{32}', target['harborShipId']), 'Invalid target runtime identity'
    registered = _harbor(api, '')
    assert registered['pierPath'] == target['pier'] and registered['identity'] == target['ship'], 'Wrong target runtime identity'
    required = {'connect', 'total marked', 'free lists', 'sweep', 'loom'}
    for attempt in range(3):
        checkpoint = _checkpoint(api); before = resource(api)
        # Print a fresh marker when Dojo executes this exact request. The wide
        # ~& form traces the marker, then produces the same unit-valued
        # %helm-mass poke as |mass. @tas tags accept letters and hyphens.
        marker = 'connect-soak-memory-' + uuid.uuid4().hex.translate(str.maketrans('0123456789', 'ghijklmnop'))
        _harbor(api, 'terminal/input', {'input': ':hood &helm-mass ~&(%' + marker + ' ~)\r'})
        deadline = time.monotonic() + 90
        after = ''; scalars = {}
        while time.monotonic() < deadline:
            time.sleep(.1)
            after = _harbor(api, 'logs')['output']
            plain = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', after).replace('\r', '')
            # Harbor retains a rolling buffer. Anchor to the executed marker,
            # not the entire previous buffer or a partial command echo.
            short_prompt = target['ship'][:7] + '_' + target['ship'][-6:] + ':dojo>'
            prompts = '|'.join(re.escape(prompt) for prompt in [short_prompt, target['ship'] + ':dojo>'])
            prompt = r'(?:' + prompts + r')[ \t]*'
            # Dojo's progress display can leave backspace/redraw history before
            # the current prompt without a newline. Require that exact prompt
            # at the end of any such history; command echoes still end in ~).
            prefix = r'(?:[ \t]*(?:' + prompt + r')?|[^\n]*\x08[^\n]*' + prompt + r')'
            anchors = list(re.finditer(r'(?m)^' + prefix + '%' + marker + r'[ \t]*$', plain))
            assert len(anchors) <= 1, 'Ambiguous target memory report marker'
            echo = ':hood &helm-mass ~&(%' + marker + ' ~)'
            assert all(anchor.group().replace(echo, '').count('%' + marker) == 1 for anchor in anchors), 'Ambiguous target memory report marker'
            if not anchors: continue
            fresh = plain[anchors[0].end():]
            pairs = re.findall(r'(?m)^\s*(connect|total marked|free lists|sweep|loom):\s*(?:B|KB|MB|GB)/(\d[\d.]*)\s*$', fresh)
            ordered = ['connect', 'total marked', 'free lists', 'sweep', 'loom']
            assert [name for name, _ in pairs] == ordered[:len(pairs)], 'Target memory report ordering is invalid'
            scalars = {name: int(value.replace('.', '')) for name, value in pairs}
            if required <= scalars.keys():
                break
        else:
            raise AssertionError('Target memory report did not complete')
        measured = resource(api)
        unchanged = checkpoint == _checkpoint(api)
        # Raw terminal output may include owner credentials. Keep it on the
        # private reference host; the scalar report never includes its contents.
        fd = os.open(ROOT / ('soak-memory-' + uuid.uuid4().hex + '.log'), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as stream: stream.write(after)
        assert measured['runtimeIdentity'] == before['runtimeIdentity'], 'Target runtime changed during memory report'
        assert 0 < scalars['connect'] <= scalars['total marked'] <= scalars['loom'], 'Invalid retained memory report'
        if unchanged:
            return measured | {'memoryMeasurement': MEMORY_MEASUREMENT, 'memoryMeasurementAttempts': attempt + 1,
                               'retainedHeapBytes': scalars['total marked'], 'connectRetainedBytes': scalars['connect'],
                               'heapFreeBytes': scalars['free lists'], 'heapSweepBytes': scalars['sweep'], 'loomBytes': scalars['loom']}
    raise AssertionError('Runtime checkpoint crossed every memory measurement')


def run():
    assert (ROOT / 'reference-update.json').is_file() and (ROOT / 'reference-load.json').is_file(), 'Install/update/load must pass first'
    report_path = ROOT / 'soak.json'; state_path = ROOT / 'soak-state.json'
    assert not report_path.exists() and not state_path.exists(), 'Existing soak evidence must be inspected; do not silently restart'
    assert not (ROOT / 'netem.json').exists(), 'Packet fixture must be cleaned up before the normal-network soak'
    api = Reference(); app = api.register(); space = app['namespace']; api.erase(space)
    grant = api.connect(); token = grant['access_token']
    state = {'grant': grant, 'refreshInFlight': False}; private_save(state_path, state)
    update = json.loads((ROOT / 'reference-update.json').read_text())
    report = {'status': 'warming', 'phase': 'warmup', 'passed': False, 'realShip': True,
              'requiredDurationSeconds': DURATION, 'durationSeconds': 0,
              'deskArchiveSHA256': update['updateArchiveSHA256'],
              'sources': {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in ['real_soak.py', 'real_reference.py', 'real_load.py']},
              'cycles': 0, 'documentsCreated': 0, 'mutationEffects': 0, 'exactReceiptReplays': 0,
              'rssTolerancePercent': 15, 'memoryMeasurement': MEMORY_MEASUREMENT,
              'network': 'normal trusted HTTPS; temporary netem removed'}
    private_save(report_path, report)
    start = None
    try:
        def interrupted(*_): raise RuntimeError('Reference soak interrupted')
        signal.signal(signal.SIGTERM, interrupted)
        signal.signal(signal.SIGINT, interrupted)
        # Measure the same mixed-size workload after cleanup, rather than
        # comparing a cold ship to the earlier maximum-payload qualification.
        for cycle in range(12): churn(api, token, space, -cycle - 1)
        time.sleep(30)
        report['phase'] = 'warm-baseline'
        report['warmBaseline'] = cleanup_resource(api)
        start = time.monotonic(); refreshed = start
        report.update(status='running', startedAt=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()))
        private_save(report_path, report)
        while time.monotonic() - start < DURATION:
            cycle_start = time.monotonic()
            if cycle_start - refreshed >= 300:
                report['phase'] = 'refresh'
                state['refreshInFlight'] = True; private_save(state_path, state)
                # Lost refresh replies terminate the soak. The durable marker
                # prevents replay of a rotating single-use refresh token.
                grant = api.refresh(grant); token = grant['access_token']
                state = {'grant': grant, 'refreshInFlight': False}; private_save(state_path, state)
                refreshed = time.monotonic()
            report['phase'] = 'churn'
            effects = churn(api, token, space, report['cycles'])
            report['cycles'] += 1
            for key, count in effects.items(): report[key] += count
            report['durationSeconds'] = round(time.monotonic() - start, 3)
            report['phase'] = 'cycle-resource'
            report['latestCleanup'] = resource(api)
            assert report['latestCleanup']['runtimeIdentity'] == report['warmBaseline']['runtimeIdentity'], 'Target runtime changed during counted soak'
            report['updatedAt'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
            report['phase'] = 'idle'
            private_save(report_path, report)
            time.sleep(max(0, min(PERIOD - (time.monotonic() - cycle_start), DURATION - (time.monotonic() - start))))
        report['phase'] = 'final-cleanup'
        time.sleep(30)
        report['afterCleanup'] = cleanup_resource(api)
        growth = report['afterCleanup']['runtimeRSSBytes'] / report['warmBaseline']['runtimeRSSBytes'] - 1
        heap_growth = report['afterCleanup']['retainedHeapBytes'] / report['warmBaseline']['retainedHeapBytes'] - 1
        report['postCleanupRSSGrowthPercent'] = round(growth * 100, 3)
        report['postCleanupHeapGrowthPercent'] = round(heap_growth * 100, 3)
        report['allocatedEventLogGrowthBytes'] = report['afterCleanup']['allocatedEventLogBytes'] - report['warmBaseline']['allocatedEventLogBytes']
        report['allocatedPierGrowthBytes'] = report['afterCleanup']['allocatedPierBytes'] - report['warmBaseline']['allocatedPierBytes']
        assert report['afterCleanup']['runtimeIdentity'] == report['warmBaseline']['runtimeIdentity'], 'Target runtime changed during counted soak'
        assert growth <= .15, 'Post-cleanup memory exceeded the 15 percent warm-baseline gate'
        assert heap_growth <= .15, 'Retained heap exceeded the 15 percent warm-baseline gate'
        report.update(status='passed', phase='complete', passed=True, durationSeconds=round(time.monotonic() - start, 3), completedAt=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()))
    except Exception as error:
        locations = [{'file': Path(frame.filename).name, 'line': frame.lineno, 'function': frame.name}
                     for frame in traceback.extract_tb(error.__traceback__)
                     if Path(frame.filename).parent == Path(__file__).parent]
        report.update(status='failed', passed=False, failureType=type(error).__name__, durationSeconds=round(time.monotonic() - start, 3) if start is not None else 0,
                      refreshAmbiguous=state['refreshInFlight'], failureLocation=locations[-1] if locations else None,
                      lastRequest=getattr(api, 'last_request', None))
        private_save(report_path, report)
        raise RuntimeError('Reference soak failed; retain private state and inspect the scalar report') from None
    private_save(report_path, report)


if __name__ == '__main__': run()
