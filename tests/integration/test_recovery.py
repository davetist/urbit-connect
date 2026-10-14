import concurrent.futures
import json
import time
import unittest
from support import API,CLIENT,REDIRECT
from test_documents import mutation,put

C='connect-recovery-test';R='org.example.connect.recovery:/callback'
class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.api=API();self.api.setup();self.space=self.api.register(C,R,'Recovery tests')['namespace']
        status,_,_=self.api.request('/connect/owner/v1/namespaces/'+self.space+'/erase','POST',{'confirmNamespace':self.space},owner=True);self.assertEqual(status,200)
    def test_journal_byte_gap_requires_snapshot(self):
        token=self.api.connect(C,R)['access_token']
        status,snapshot,_=self.api.request('/connect/v1/snapshots','POST',{},token=token);self.assertEqual(status,200)
        op=put(data={'text':'x'*15000});revision=None
        for _ in range(72):
            op['expectedRevision']=revision
            status,commit,_=self.api.request('/connect/v1/mutations','POST',mutation(op),token=token);self.assertEqual(status,200);revision=commit['revision']
        status,error,_=self.api.request('/connect/v1/changes?after='+snapshot['atCursor'],token=token)
        self.assertEqual(status,410);self.assertEqual(error['error']['code'],'cursor_expired')
    def test_one_session_revocation_keeps_other_sessions_and_apps(self):
        a=self.api.connect(C,R);b=self.api.connect(C,R);other=self.api.connect()
        op=put();self.assertEqual(self.api.request('/connect/v1/mutations','POST',mutation(op),token=a['access_token'])[0],200)
        status,snapshot,_=self.api.request('/connect/v1/snapshots','POST',{},token=a['access_token']);self.assertEqual(status,200)
        self.assertEqual(self.api.request('/connect/owner/v1/revoke','POST',{'sessionId':a['grant']['sessionId']},owner=True)[0],200)
        self.assertEqual(self.api.request('/connect/v1/snapshots/'+snapshot['snapshotId'],token=a['access_token'])[0],401)
        self.assertEqual(self.api.request('/connect/oauth/token','POST',{'grant_type':'refresh_token','client_id':C,'refresh_token':a['refresh_token']},form=True)[0],400)
        self.assertEqual(self.api.request('/connect/v1/collections/lists/documents/'+op['id'],token=b['access_token'])[0],200)
        self.assertEqual(self.api.request('/connect/v1/identity',token=other['access_token'])[0],200)
        self.assertEqual(self.api.request('/connect/owner/v1/namespaces/'+self.space+'/documents',owner=True)[1]['documents'][0]['id'],op['id'])
    def test_snapshot_and_authorization_code_expire_on_real_ship_time(self):
        tokens=self.api.connect(C,R);token=tokens['access_token']
        status,snapshot,_=self.api.request('/connect/v1/snapshots','POST',{},token=token);self.assertEqual(status,200)
        result,_,verifier=self.api.begin(C,R);callback=self.api.approve(result)
        time.sleep(31);time.sleep(31)
        status,error,_=self.api.request('/connect/v1/snapshots/'+snapshot['snapshotId'],token=token)
        self.assertEqual(status,410);self.assertEqual(error['error']['code'],'snapshot_expired')
        status,_,_=self.api.request('/connect/oauth/token','POST',{'grant_type':'authorization_code','client_id':C,'redirect_uri':R,'code':callback['code'][0],'code_verifier':verifier},form=True)
        self.assertEqual(status,400)
    def test_z_restore_epoch_revokes_all_old_tokens_and_preserves_documents(self):
        tokens=self.api.connect(C,R);op=put();body=mutation(op)
        self.assertEqual(self.api.request('/connect/v1/mutations','POST',body,token=tokens['access_token'])[0],200)
        status,before,_=self.api.request('/connect/v1/identity',token=tokens['access_token']);self.assertEqual(status,200)
        status,after,_=self.api.request('/connect/owner/v1/restore-epoch','POST',{'confirmInstanceId':before['account']['instanceId']},owner=True);self.assertEqual(status,200)
        self.assertNotEqual(after['syncEpoch'],before['account']['syncEpoch'])
        self.assertEqual(self.api.request('/connect/v1/mutations','POST',body,token=tokens['access_token'])[0],401)
        fresh=self.api.connect(C,R);self.assertEqual(self.api.request('/connect/v1/collections/lists/documents/'+op['id'],token=fresh['access_token'])[0],200)
if __name__=='__main__':unittest.main()
