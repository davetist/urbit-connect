import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock,patch

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
import netem_host
from native_harness import teardown
from real_test_support import RealAPI


class FixtureCleanup(unittest.TestCase):
    def test_capacity_restore_failure_still_closes_server_and_recovers_ingress(self):
        server=Mock();metadata=Mock();recover=Mock()
        with self.assertRaises(RuntimeError):teardown(server,metadata,recover,Mock(side_effect=RuntimeError('restore failed')))
        server.shutdown.assert_called_once();server.server_close.assert_called_once();metadata.unlink.assert_called_once();recover.assert_called_once()

    def test_server_close_failure_still_recovers_ingress(self):
        server=Mock();server.server_close.side_effect=OSError('close failed');recover=Mock()
        with self.assertRaises(OSError):teardown(server,Mock(),recover,Mock())
        recover.assert_called_once()

    def test_lost_start_reply_retains_run_ownership_for_teardown(self):
        api=RealAPI.__new__(RealAPI);api.packet_fixture=False;api.packet_run='a'*32
        api.remote=Mock(side_effect=[RuntimeError('reply lost'),b'{"stopped":true}'])
        with self.assertRaises(RuntimeError):api.packet_profile('100ms-1percent')
        self.assertTrue(api.packet_fixture)
        api.stop_packet_fixture()
        self.assertEqual(api.remote.call_args.args[0][-2:],['stop','a'*32]);self.assertFalse(api.packet_fixture)

    def test_slirp_launch_failure_terminates_its_allocated_namespace(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'target.json').write_text(json.dumps({'pier':'/mnt/harbor/piers/connect-dev'}))
            child=Mock(pid=123);child.poll.return_value=None
            with patch.multiple(netem_host,ROOT=root,SOCKET=root/'control.sock',METADATA=root/'metadata.json',STARTING=root/'starting.json'),patch.object(netem_host,'require_target'),patch.object(netem_host.signal,'signal'),patch.object(netem_host.subprocess,'Popen',side_effect=[child,OSError('slirp unavailable')]):
                with self.assertRaises(OSError):netem_host.serve('b'*32)
            child.terminate.assert_called_once();child.wait.assert_called_once()
            self.assertTrue(json.loads((root/('netem-outcome-'+'b'*32+'.json')).read_text())['childrenStopped'])

    def test_stop_propagates_recorded_restoration_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);id='c'*32
            (root/('netem-outcome-'+id+'.json')).write_text(json.dumps({'runID':id,'childrenStopped':True,'ingressRestored':False,'cleanupError':'TimeoutExpired'}))
            with patch.multiple(netem_host,ROOT=root,SOCKET=root/'control.sock',METADATA=root/'metadata.json',STARTING=root/'starting.json'):
                with self.assertRaisesRegex(RuntimeError,'teardown failed'):netem_host.stop(id)

    def test_stop_waits_for_restoration_receipt_and_marker_cleanup(self):
        import threading,time
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);id='d'*32;metadata=root/'metadata.json';metadata.write_text(json.dumps({'runID':id}))
            outcome=root/('netem-outcome-'+id+'.json')
            def finish():
                outcome.write_text(json.dumps({'runID':id,'childrenStopped':True,'ingressRestored':True}));metadata.unlink()
            with patch.multiple(netem_host,ROOT=root,SOCKET=root/'control.sock',METADATA=metadata,STARTING=root/'starting.json'),patch.object(netem_host,'control',return_value={'stopping':True}):
                timer=threading.Timer(.05,finish);timer.start();start=time.monotonic()
                result=netem_host.stop(id);timer.join()
                self.assertGreaterEqual(time.monotonic()-start,.05);self.assertTrue(result['childrenStopped']);self.assertFalse(metadata.exists())


if __name__=='__main__':unittest.main()
