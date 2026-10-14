import json
from pathlib import Path
import subprocess
import sys
import unittest
from support import API,ROOT
from test_documents import mutation,put
sys.path.insert(0,str(ROOT/'scripts'))
from dev_ship import rpc
class LifecycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.api=API();cls.api.setup();cls.api.register('connect-lifecycle-test','org.example.connect.lifecycle:/callback','Lifecycle tests')
    def test_acknowledged_commit_and_receipt_survive_clean_and_abrupt_restart(self):
        tokens=self.api.connect('connect-lifecycle-test','org.example.connect.lifecycle:/callback');token=tokens['access_token']
        operation=put(data={'title':'Survives runtime restart'});body=json.dumps(mutation(operation),separators=(',',':')).encode()
        status,receipt,_=self.api.request('/connect/v1/mutations','POST',body,token=token);self.assertEqual(status,200)
        for action in ['stop','crash']:
            with self.subTest(action=action):
                rpc(ROOT/'.work/alpha/dev',action,timeout=100)
                subprocess.run([sys.executable,str(ROOT/'scripts/dev_ship.py'),'start'],check=True,capture_output=True)
                status,row,_=self.api.request('/connect/v1/collections/lists/documents/'+operation['id'],token=token)
                self.assertEqual(status,200);self.assertEqual(row['data'],operation['data'])
                status,retry,_=self.api.request('/connect/v1/mutations','POST',body,token=token)
                self.assertEqual(status,200);self.assertEqual(retry,receipt)
    def test_agent_reload_preserves_documents_and_receipts(self):
        tokens=self.api.connect('connect-lifecycle-test','org.example.connect.lifecycle:/callback');token=tokens['access_token']
        op=put();body=json.dumps(mutation(op),separators=(',',':')).encode();status,receipt,_=self.api.request('/connect/v1/mutations','POST',body,token=token);self.assertEqual(status,200)
        target=ROOT/'.work/alpha/dev/zod/connect/app/connect.hoon';source=(ROOT/'desk/app/connect.hoon').read_bytes()
        try:
            target.write_bytes(b'::  Isolated acceptance reload.\n'+source)
            output=rpc(ROOT/'.work/alpha/dev','command',command='|commit %connect',timeout=120)['output']
            self.assertNotIn('FAILED',output)
            status,retry,_=self.api.request('/connect/v1/mutations','POST',body,token=token)
            self.assertEqual(status,200);self.assertEqual(retry,receipt)
        finally:
            target.write_bytes(source);rpc(ROOT/'.work/alpha/dev','command',command='|commit %connect',timeout=120)
if __name__=='__main__':unittest.main()
