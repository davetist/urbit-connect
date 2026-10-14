import json
import unittest
import uuid
from support import API

def ident(): return str(uuid.uuid4())
def put(document=None,expected=None,data=None):
    return {'type':'put','collection':'lists','id':document or ident(),'expectedRevision':expected,'data':data if data is not None else {'title':'Personal','tasks':[]}}
def mutation(*operations): return {'requestId':ident(),'operations':list(operations)}

class DocumentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.api=API();cls.api.setup()
        cls.a=cls.api.connect()['access_token']
        cls.api.register('connect-second-prototype','org.example.urbitconnect.second:/oauth/callback','Second application')
        cls.b=cls.api.connect('connect-second-prototype','org.example.urbitconnect.second:/oauth/callback')['access_token']
    def write(self,body,token=None):return self.api.request('/connect/v1/mutations','POST',body,token=token or self.a)
    def read(self,id,token=None):return self.api.request('/connect/v1/collections/lists/documents/'+id,token=token or self.a)
    def test_create_update_delete_and_tombstone(self):
        op=put();status,commit,_=self.write(mutation(op));self.assertEqual(status,200)
        rev=commit['revision'];status,row,_=self.read(op['id']);self.assertEqual(status,200)
        self.assertEqual(row['data']['title'],'Personal')
        status,commit,_=self.write(mutation(put(op['id'],rev,{'title':'Changed'})));self.assertEqual(status,200)
        status,_,_=self.write(mutation({'type':'delete','collection':'lists','id':op['id'],'expectedRevision':commit['revision']}));self.assertEqual(status,200)
        self.assertEqual(self.read(op['id'])[0],404)
        self.assertEqual(self.write(mutation(put(op['id'],rev)))[0],409)
        self.assertEqual(self.write(mutation(put(op['id'])))[0],409)
    def test_atomic_conflict_and_duplicate_target(self):
        op=put();self.assertEqual(self.write(mutation(op))[0],200)
        other=put();self.assertEqual(self.write(mutation(other,op))[0],409)
        self.assertEqual(self.read(other['id'])[0],404)
        self.assertEqual(self.write(mutation(other,other))[0],400)
    def test_exact_bytes_retry_and_changed_body(self):
        op=put();body=mutation(op);raw=json.dumps(body,separators=(',',':')).encode()
        status,first,_=self.write(raw);self.assertEqual(status,200)
        status,again,_=self.write(raw);self.assertEqual(status,200);self.assertEqual(first,again)
        status,error,_=self.write(json.dumps(body,indent=2).encode());self.assertEqual(status,409)
        self.assertEqual(error['error']['code'],'idempotency_mismatch')
    def test_namespace_isolation_and_override_rejected(self):
        op=put();self.assertEqual(self.write(mutation(op))[0],200)
        self.assertEqual(self.read(op['id'],self.b)[0],404)
        body=mutation(put());body['namespace']='other'
        self.assertEqual(self.write(body,self.b)[0],400)
        self.assertEqual(self.api.request('/connect/owner/v1/clients',token=self.b)[0],401)
    def test_invalid_json_never_stops_agent(self):
        for raw in [b'{"requestId":"x","requestId":"y"}',b'{',b'{"namespace":"victim"}',b'null']:
            self.assertEqual(self.write(raw)[0],400)
        self.assertEqual(self.api.request('/connect/v1/info')[0],200)
    def test_snapshot_is_consistent_across_later_write(self):
        op=put();self.assertEqual(self.write(mutation(op))[0],200)
        status,snapshot,_=self.api.request('/connect/v1/snapshots','POST',{},token=self.a)
        self.assertEqual(status,200)
        late=put();self.assertEqual(self.write(mutation(late))[0],200)
        status,page,_=self.api.request('/connect/v1/snapshots/'+snapshot['snapshotId'],token=self.a)
        self.assertEqual(status,200)
        self.assertNotIn(late['id'],[d['id'] for d in page['documents']])
        self.assertEqual(self.api.request('/connect/v1/snapshots/'+snapshot['snapshotId'],token=self.b)[0],404)
        status,changes,_=self.api.request('/connect/v1/changes?after='+snapshot['atCursor'],token=self.a)
        self.assertEqual(status,200)
        self.assertIn(late['id'],[c['document']['id'] for b in changes['batches'] for c in b['changes'] if 'document' in c])

if __name__=='__main__':unittest.main()
