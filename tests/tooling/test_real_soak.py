import json
import re
from copy import deepcopy
import tempfile
from unittest.mock import patch
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import real_soak


class MemoryAPI:
    def __init__(self, lose_reply=False, corrupt=False):
        self.rows = {}; self.receipts = {}; self.revision = 0
        self.lose_reply = lose_reply; self.corrupt = corrupt; self.bodies = []
    def documents(self, _): return list(self.rows.values())
    def request(self, path, method, raw, token):
        self.bodies.append(raw); body = json.loads(raw); id = body['requestId']
        if id in self.receipts:
            previous, receipt = self.receipts[id]; assert previous == raw
            return 200, receipt
        self.revision += 1
        for op in body['operations']:
            if op['type'] == 'put':
                self.rows[op['id']] = {'id': op['id'], 'data': op['data'] if not self.corrupt else {}, 'revision': str(self.revision)}
            else: self.rows.pop(op['id'])
        receipt = {'revision': str(self.revision)}; self.receipts[id] = (raw, receipt)
        if self.lose_reply:
            self.lose_reply = False; raise RuntimeError('reply withheld after commit')
        return 200, receipt


class SoakWorkload(unittest.TestCase):
    def test_withheld_committed_reply_reuses_exact_bytes_and_has_one_effect(self):
        api = MemoryAPI(lose_reply=True)
        self.assertEqual(real_soak.churn(api, 'private', 'space', 1)['mutationEffects'], 3)
        self.assertEqual(api.revision, 3); self.assertEqual(api.rows, {})
        self.assertEqual(api.bodies[0], api.bodies[1]); self.assertEqual(api.bodies[1], api.bodies[2])

    def test_acknowledged_data_divergence_fails_the_soak(self):
        with self.assertRaisesRegex(AssertionError, 'Acknowledged records'):
            real_soak.churn(MemoryAPI(corrupt=True), 'private', 'space', 1)


class SimulatedClock:
    def __init__(self): self.seconds = 0
    def monotonic(self): return self.seconds
    def sleep(self, seconds): self.seconds += seconds


class LifecycleAPI(MemoryAPI):
    def register(self): return {'namespace': 'space'}
    def erase(self, _): self.rows.clear()
    def connect(self): return {'access_token': 'unit-test-private-token'}
    def refresh(self, _): return self.connect()


class CleanupMemoryBoundary(unittest.TestCase):
    target = {'project': '/absolute/project',
              'pier': '/mnt/harbor/piers/connect-dev',
              'ship': '~zod',
              'harborShipId': '00000000000000000000000000000000'}
    profile = ('\r\n  connect: KB/5.000\r\n'
               'total marked: MB/100.000.000\r\n'
               'free lists: MB/100.000.000\r\n'
               'sweep: MB/100.000.128\r\n'
               'loom: GB/2.147.483.648\r\n')

    def measure(self, checkpoints=None, after_process=None, profile=None, prefix='', rollover=False, omit_echo=False,
                after_marker_prefix='', duplicate_marker=False, trace_prompt=False, trace_redraw=False,
                duplicate_redraw_marker=False, redraw_command_echo=False):
        api = LifecycleAPI(); api.target = self.target.copy()
        identity = {'bootId': 'fixture-boot', 'processes': [{'pid': 12, 'startTicks': 123}]}
        before = {'runtimeRSSBytes': 10000000, 'runtimeIdentity': identity}
        after = {'runtimeRSSBytes': 110000000, 'runtimeIdentity': after_process or identity}
        terminal = 'private-credential-canary\r\n~sopwyn_marzod:dojo> '
        calls = []
        def harbor(_, route, body=None):
            calls.append((route, body))
            if route == '': return {'pierPath': self.target['pier'], 'identity': self.target['ship']}
            if route == 'terminal/input': return None
            command = next(body['input'] for route, body in reversed(calls) if route == 'terminal/input')
            marker = re.search(r'%(connect-soak-memory-[a-p]{32}) ~\)', command).group(1)
            trace = '~sopwyn_marzod:dojo> ' if trace_prompt else '  '
            if trace_redraw:
                trace = '~sopwyn_marzod:dojo> http' + '\x08' * 4 + trace
            if duplicate_redraw_marker:
                trace = '~sopwyn_marzod:dojo> %' + marker + '\x08' * 4 + trace
            if redraw_command_echo:
                trace = command.replace('\r', '') + '\x08' * 4 + trace
            echoed = '' if omit_echo else command.replace('\r', '\n') + trace + '%' + marker + '\n'
            if duplicate_marker: echoed += '  %' + marker + '\n'
            return {'output': (terminal[-20:] if rollover else terminal) + prefix + echoed + after_marker_prefix + (self.profile if profile is None else profile)}
        with tempfile.TemporaryDirectory() as folder, \
             patch.object(real_soak, 'ROOT', Path(folder)), \
             patch.object(real_soak, '_harbor', side_effect=harbor), \
             patch.object(real_soak, '_checkpoint', side_effect=checkpoints or [('fixture',)] * 2), \
             patch.object(real_soak, 'resource', side_effect=[before, after] * 3), \
             patch.object(real_soak.time, 'sleep'):
            result = real_soak.cleanup_resource(api)
            private = list(Path(folder).glob('soak-memory-*.log'))
            self.assertTrue(private)
            self.assertTrue(all(path.stat().st_mode & 0o777 == 0o600 for path in private))
            self.assertNotIn('private-credential-canary', json.dumps(result))
        return result, calls

    def test_samples_after_completed_heap_walk_instead_of_cold_residency(self):
        result, calls = self.measure()
        self.assertEqual(result['runtimeRSSBytes'], 110000000)
        self.assertEqual(result['retainedHeapBytes'], 100000000)
        self.assertEqual(result['connectRetainedBytes'], 5000)
        self.assertEqual(result['memoryMeasurement'], 'vere-mass-sweep-resident-v1')
        inputs = [body['input'] for route, body in calls if route == 'terminal/input']
        self.assertEqual(len(inputs), 1)
        self.assertRegex(inputs[0], r'^:hood &helm-mass ~&\(%connect-soak-memory-[a-p]{32} ~\)\r$')

    def test_discards_checkpoint_crossing_and_repeats_same_measurement(self):
        result, calls = self.measure(checkpoints=[('old',), ('new',), ('new',), ('new',)])
        self.assertEqual(result['memoryMeasurementAttempts'], 2)
        self.assertEqual(sum(route == 'terminal/input' for route, _ in calls), 2)

    def test_continuous_checkpoint_crossings_fail_closed(self):
        with self.assertRaisesRegex(AssertionError, 'checkpoint'):
            self.measure(checkpoints=[(n,) for n in range(6)])

    def test_restart_during_boundary_fails_closed(self):
        with self.assertRaisesRegex(AssertionError, 'runtime'):
            self.measure(after_process={'bootId': 'new-boot', 'processes': [{'pid': 12, 'startTicks': 123}]})

    def test_incomplete_heap_report_cannot_produce_a_measurement(self):
        with patch.object(real_soak.time, 'monotonic', side_effect=[0, 1, 1000]):
            with self.assertRaisesRegex(AssertionError, 'memory report'):
                self.measure(profile='total marked: MB/100.000.000\n')

    def test_older_tail_and_new_partial_report_cannot_be_combined(self):
        old_tail = self.profile[self.profile.index('total marked:'):].replace('100.000.000', '80.000.000')
        with patch.object(real_soak.time, 'monotonic', side_effect=[0, 1, 1000]):
            with self.assertRaisesRegex(AssertionError, 'memory report'):
                self.measure(prefix=old_tail, profile='  connect: KB/5.000\n')

    def test_older_tail_before_tagged_frame_is_excluded(self):
        old_tail = self.profile[self.profile.index('total marked:'):].replace('100.000.000', '80.000.000')
        result, _ = self.measure(prefix=old_tail)
        self.assertEqual(result['retainedHeapBytes'], 100000000)

    def test_rolling_log_can_evict_old_output_without_losing_current_frame(self):
        result, _ = self.measure(rollover=True)
        self.assertEqual(result['retainedHeapBytes'], 100000000)

    def test_executed_trace_at_the_approved_prompt_is_a_valid_marker(self):
        result, _ = self.measure(trace_prompt=True)
        self.assertEqual(result['retainedHeapBytes'], 100000000)

    def test_prompt_redraw_before_executed_trace_does_not_hide_current_frame(self):
        with patch.object(real_soak.time, 'monotonic', side_effect=[0, 1, 1000]):
            result, _ = self.measure(trace_prompt=True, trace_redraw=True)
        self.assertEqual(result['retainedHeapBytes'], 100000000)

    def test_redraw_history_without_the_approved_prompt_fails_closed(self):
        with patch.object(real_soak.time, 'monotonic', side_effect=[0, 1, 1000]):
            with self.assertRaisesRegex(AssertionError, 'memory report'):
                self.measure(trace_redraw=True)

    def test_same_line_duplicate_executed_marker_is_not_hidden_by_redraw(self):
        with self.assertRaisesRegex(AssertionError, 'memory report'):
            self.measure(trace_prompt=True, duplicate_redraw_marker=True)

    def test_full_command_echo_in_redraw_history_is_not_an_executed_marker(self):
        result, _ = self.measure(trace_prompt=True, redraw_command_echo=True)
        self.assertEqual(result['retainedHeapBytes'], 100000000)

    def test_report_without_current_command_marker_fails_closed(self):
        with patch.object(real_soak.time, 'monotonic', side_effect=[0, 1, 1000]):
            with self.assertRaisesRegex(AssertionError, 'memory report'):
                self.measure(rollover=True, omit_echo=True)

    def test_old_summary_after_current_marker_is_not_a_new_frame(self):
        old_tail = self.profile[self.profile.index('total marked:'):]
        with self.assertRaisesRegex(AssertionError, 'memory report'):
            self.measure(after_marker_prefix=old_tail, profile='  connect: KB/5.000\n')

    def test_duplicate_current_frames_or_markers_fail_closed(self):
        with self.assertRaisesRegex(AssertionError, 'memory report'):
            self.measure(profile=self.profile * 2)
        with self.assertRaisesRegex(AssertionError, 'memory report'):
            self.measure(duplicate_marker=True)


class SoakDuration(unittest.TestCase):
    def test_integrity_failure_retains_assertion_location_without_private_state(self):
        api = LifecycleAPI(corrupt=True)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'reference-update.json').write_text('{"updateArchiveSHA256":"fixture"}')
            (root / 'reference-load.json').write_text('{}')
            for name in ['real_soak.py', 'real_reference.py', 'real_load.py']:
                (root / name).write_text('unit-test-source-fixture')
            with patch.object(real_soak, 'ROOT', root), patch.object(real_soak, 'Reference', return_value=api), \
                 patch.object(real_soak.signal, 'signal'):
                with self.assertRaises(RuntimeError): real_soak.run()
            report = json.loads((root / 'soak.json').read_text())
        self.assertEqual(report['status'], 'failed')
        self.assertEqual(report.get('phase'), 'warmup')
        location = report.get('failureLocation', {})
        self.assertEqual(location.get('file'), 'real_soak.py')
        self.assertEqual(location.get('function'), 'churn')
        self.assertGreater(location.get('line', 0), 0)
        self.assertNotIn('unit-test-private-token', json.dumps(report))

    def test_fresh_run_stops_after_six_hours_and_final_cleanup(self):
        clock = SimulatedClock(); api = LifecycleAPI()
        resources = {'runtimeRSSBytes': 100000, 'allocatedPierBytes': 200000,
                     'allocatedEventLogBytes': 150000, 'retainedHeapBytes': 200000,
                     'runtimeIdentity': {'bootId': 'fixture', 'processes': [{'pid': 12, 'startTicks': 123}]}}
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'reference-update.json').write_text('{"updateArchiveSHA256":"fixture"}')
            (root / 'reference-load.json').write_text('{}')
            for name in ['real_soak.py', 'real_reference.py', 'real_load.py']:
                (root / name).write_text('unit-test-source-fixture')
            with patch.object(real_soak, 'ROOT', root), patch.object(real_soak, 'Reference', return_value=api), \
                 patch.object(real_soak, 'resource', side_effect=lambda _: deepcopy(resources)), \
                 patch.object(real_soak, 'cleanup_resource', side_effect=lambda _: deepcopy(resources)), \
                 patch.object(real_soak.time, 'monotonic', clock.monotonic), \
                 patch.object(real_soak.time, 'sleep', clock.sleep), patch.object(real_soak.signal, 'signal'):
                real_soak.run()
            report = json.loads((root / 'soak.json').read_text())
        self.assertEqual(report['status'], 'passed')
        self.assertEqual(report['durationSeconds'], 21630)
        self.assertEqual(report['cycles'], 180)
        self.assertEqual(report['documentsCreated'], 720)
        self.assertEqual(report['mutationEffects'], 540)
        self.assertEqual(report['exactReceiptReplays'], 540)
        self.assertEqual(report['postCleanupRSSGrowthPercent'], 0)
        self.assertEqual(report['allocatedPierGrowthBytes'], 0)
        self.assertEqual(api.rows, {})

    def test_rss_or_heap_growth_above_fifteen_percent_still_fails(self):
        for rss, heap, message in [(116, 100, 'Post-cleanup memory'), (100, 116, 'Retained heap')]:
            with self.subTest(rss=rss, heap=heap), tempfile.TemporaryDirectory() as folder:
                clock = SimulatedClock(); api = LifecycleAPI(); root = Path(folder)
                for name, value in [('reference-update.json', '{"updateArchiveSHA256":"fixture"}'),
                                    ('reference-load.json', '{}')]: (root / name).write_text(value)
                for name in ['real_soak.py', 'real_reference.py', 'real_load.py']: (root / name).write_text('fixture')
                before = {'runtimeRSSBytes': 100, 'retainedHeapBytes': 100, 'allocatedPierBytes': 0,
                          'allocatedEventLogBytes': 0, 'runtimeIdentity': {'bootId': 'fixture', 'processes': []}}
                after = before | {'runtimeRSSBytes': rss, 'retainedHeapBytes': heap}
                with patch.object(real_soak, 'ROOT', root), patch.object(real_soak, 'Reference', return_value=api), \
                     patch.object(real_soak, 'resource', side_effect=lambda _: deepcopy(before)), \
                     patch.object(real_soak, 'cleanup_resource', side_effect=[before, after]), \
                     patch.object(real_soak.time, 'monotonic', clock.monotonic), \
                     patch.object(real_soak.time, 'sleep', clock.sleep), patch.object(real_soak.signal, 'signal'):
                    with self.assertRaises(RuntimeError): real_soak.run()
                report = json.loads((root / 'soak.json').read_text())
                self.assertEqual(report['status'], 'failed'); self.assertFalse(report['passed'])
                self.assertEqual(report['durationSeconds'], 21630)
                self.assertEqual(report['cycles'], 180)
                self.assertEqual(report['postCleanupRSSGrowthPercent'], rss - 100)
                self.assertEqual(report['postCleanupHeapGrowthPercent'], heap - 100)
                self.assertNotIn('unit-test-private-token', json.dumps(report))


if __name__ == '__main__': unittest.main()
