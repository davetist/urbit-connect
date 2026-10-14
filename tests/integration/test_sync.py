import concurrent.futures
import time
import unittest
from support import API,CLIENT
from test_documents import mutation,put

class SyncTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.api=API();cls.api.setup()
    def setUp(self):
        # Each poll test owns its sessions. Do not retain snapshots from an
        # unrelated previous test and accidentally test the app's capacity cap.
        self.assertEqual(self.api.request('/connect/owner/v1/revoke','POST',{'clientId':CLIENT},owner=True)[0],200)
    def tearDown(self):
        self.assertEqual(self.api.request('/connect/owner/v1/revoke','POST',{'clientId':CLIENT},owner=True)[0],200)
    def test_pending_poll_delivers_write(self):
        tokens=self.api.connect();token=tokens['access_token']
        status,snapshot,_=self.api.request('/connect/v1/snapshots','POST',{},token=token);self.assertEqual(status,200)
        after=snapshot['atCursor']
        with concurrent.futures.ThreadPoolExecutor() as pool:
            pending=pool.submit(self.api.request,'/connect/v1/changes?after='+after+'&wait=25',token=token)
            time.sleep(.3)
            self.assertFalse(pending.done())
            op=put();status,_,_=self.api.request('/connect/v1/mutations','POST',mutation(op),token=token);self.assertEqual(status,200)
            status,change,_=pending.result(timeout=3);self.assertEqual(status,200)
            self.assertIn(op['id'],[c['document']['id'] for b in change['batches'] for c in b['changes'] if 'document'in c])
    def test_pending_poll_revocation_returns_401(self):
        tokens=self.api.connect();token=tokens['access_token']
        status,snapshot,_=self.api.request('/connect/v1/snapshots','POST',{},token=token);self.assertEqual(status,200)
        with concurrent.futures.ThreadPoolExecutor() as pool:
            pending=pool.submit(self.api.request,'/connect/v1/changes?after='+snapshot['atCursor']+'&wait=25',token=token)
            time.sleep(.3);self.assertFalse(pending.done())
            status,_,_=self.api.request('/connect/oauth/revoke','POST',{},token=token);self.assertEqual(status,200)
            self.assertEqual(pending.result(timeout=3)[0],401)
    def test_poll_timeout_and_one_per_session(self):
        tokens=self.api.connect();token=tokens['access_token']
        status,snapshot,_=self.api.request('/connect/v1/snapshots','POST',{},token=token);self.assertEqual(status,200)
        with concurrent.futures.ThreadPoolExecutor() as pool:
            start=time.monotonic()
            pending=pool.submit(self.api.request,'/connect/v1/changes?after='+snapshot['atCursor']+'&wait=1',token=token)
            time.sleep(.2)
            self.assertEqual(self.api.request('/connect/v1/changes?after='+snapshot['atCursor']+'&wait=1',token=token)[0],429)
            status,changes,_=pending.result(timeout=3)
            self.assertEqual(status,200);self.assertEqual(changes['batches'],[])
            self.assertGreaterEqual(time.monotonic()-start,.8)

if __name__=='__main__':unittest.main()
