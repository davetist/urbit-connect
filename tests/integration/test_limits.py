import json
import time
import unittest
from support import API
from test_documents import mutation,put

CLIENT='connect-limits-test';REDIRECT='org.example.connect.limits:/callback'
class LimitsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.api=API();cls.api.setup();cls.space=cls.api.register(CLIENT,REDIRECT,'Boundary tests')['namespace']
    def setUp(self):
        status,_,_=self.api.request('/connect/owner/v1/namespaces/'+self.space+'/erase','POST',{'confirmNamespace':self.space},owner=True)
        self.assertEqual(status,200);self.token=self.api.connect(CLIENT,REDIRECT)['access_token']
    def write(self,body):return self.api.request('/connect/v1/mutations','POST',body,token=self.token)
    def test_sixteen_level_document_round_trips_all_envelopes(self):
        data={'leaf':'deep'}
        for _ in range(15):data={'child':data}
        op=put(data=data);status,commit,_=self.write(mutation(op));self.assertEqual(status,200)
        status,row,_=self.api.request('/connect/v1/collections/lists/documents/'+op['id'],token=self.token)
        self.assertEqual(status,200);self.assertEqual(row['data'],data)
        _,identity,_=self.api.request('/connect/v1/identity',token=self.token)
        status,changes,_=self.api.request('/connect/v1/changes?after='+identity['account']['syncEpoch']+':'+identity['grant']['namespaceEpoch']+':0',token=self.token)
        self.assertEqual(status,200);self.assertEqual(changes['batches'][0]['changes'][0]['document']['data'],data)
        envelope={'formatVersion':1,'source':{'issuer':'https://example.invalid/connect','instanceId':'fixture','ship':'~zod','syncEpoch':'1'},'namespace':self.space,'collections':{'lists':[row]}}
        status,preview,_=self.api.request('/connect/owner/v1/imports/validate','POST',{'namespace':self.space,'mode':'compare-and-swap','export':envelope},owner=True)
        self.assertEqual(status,200);self.assertEqual(preview['operations'][0]['data'],data)
        self.assertEqual(self.write(mutation(put(data={'child':data})))[0],400)
    def test_utf8_document_and_request_byte_bounds(self):
        # Canonical {"x":"..."} overhead is eight UTF-8 bytes.
        self.assertEqual(self.write(mutation(put(data={'x':'a'*(16384-8)})))[0],200)
        self.assertEqual(self.write(mutation(put(data={'x':'a'*(16385-8)})))[0],413)
        self.assertEqual(self.write(mutation(put(data={'x':'é'*8192})))[0],413)
        raw=json.dumps(mutation(put()),separators=(',',':')).encode()
        self.assertEqual(self.write(raw+b' '*(262144-len(raw)))[0],200)
        self.assertEqual(self.write(raw+b' '*(262145-len(raw)))[0],413)
    def test_batch_count_and_payload_atomicity(self):
        self.assertEqual(self.write(mutation(*[put()for _ in range(32)]))[0],200)
        self.assertEqual(self.write(mutation(*[put()for _ in range(33)]))[0],400)
        first=put();large=put(data={'x':'x'*16384})
        self.assertEqual(self.write(mutation(first,large))[0],413)
        self.assertEqual(self.api.request('/connect/v1/collections/lists/documents/'+first['id'],token=self.token)[0],404)
    def test_thousand_document_limit_and_stable_snapshot_pages(self):
        ids=[]
        for start in range(0,1000,32):
            ops=[put()for _ in range(min(32,1000-start))];ids.extend(o['id']for o in ops)
            self.assertEqual(self.write(mutation(*ops))[0],200)
        self.assertEqual(self.write(mutation(put()))[0],429)
        status,page,_=self.api.request('/connect/v1/snapshots','POST',{},token=self.token);self.assertEqual(status,200)
        expectedCursor=page['atCursor'];found=[]
        while True:
            found.extend(d['id']for d in page['documents'])
            self.assertEqual(page['atCursor'],expectedCursor)
            if page['nextPage']is None:break
            status,page,_=self.api.request('/connect/v1/snapshots/'+page['snapshotId']+'?page='+page['nextPage'],token=self.token);self.assertEqual(status,200)
        self.assertEqual(set(found),set(ids));self.assertEqual(len(found),1000)
    def test_namespace_payload_quota(self):
        for _ in range(16):
            ops=[put(data={'x':'a'*(16384-8)})for _ in range(16)]
            # Full 16-document request exceeds 256KiB by its envelope, so use two eight-document batches.
            for part in (ops[:8],ops[8:]):self.assertEqual(self.write(mutation(*part))[0],200)
        self.assertEqual(self.write(mutation(put(data={'x':'a'})))[0],429)
    def test_scope_checked_before_receipt_and_no_conflict_body_leak(self):
        op=put();body=mutation(op);self.assertEqual(self.write(body)[0],200)
        read=self.api.connect(CLIENT,REDIRECT,'documents:read')['access_token']
        self.assertEqual(self.api.request('/connect/v1/mutations','POST',body,token=read)[0],403)
        write=self.api.connect(CLIENT,REDIRECT,'documents:write')['access_token']
        status,error,_=self.api.request('/connect/v1/mutations','POST',mutation(op),token=write)
        self.assertEqual(status,409);self.assertIsNone(error['error']['current'])
    def test_identifier_and_pagination_rejections(self):
        for name in ['../secret','UPPER','a%2fb','é','x'*49]:
            op=put();op['collection']=name;self.assertEqual(self.write(mutation(op))[0],400)
        for id in ['../secret','00000000-0000-4000-8000-00000000000A','é','']:
            op=put();op['id']=id;self.assertEqual(self.write(mutation(op))[0],400)
        for query in ['limit=101','limit=0','namespace=other','page=-1','limit=1&limit=2']:
            self.assertEqual(self.api.request('/connect/v1/collections/lists/documents?'+query,token=self.token)[0],400)
    def test_session_rate_limit_and_revocation_precedence(self):
        # @da minute buckets do not share Unix's epoch. Observe the ship's actual
        # bucket and retry only if the burst crossed that boundary.
        import re,sys
        from pathlib import Path
        sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts'))
        from dev_ship import ROOT,rpc
        def minute():
            output=rpc(ROOT/'.work/alpha/dev','command',command='(div now ~m1)')['output']
            return re.findall(r'(?m)~zod:dojo> ([0-9][0-9.]*)\s*$',output)[-1]
        for attempt in range(2):
            before=minute()
            statuses=[self.api.request('/connect/v1/collections/lists/documents',token=self.token)[0]for _ in range(121)]
            if minute()==before:break
            self.assertEqual(self.api.request('/connect/oauth/revoke','POST',{},token=self.token)[0],200)
            self.token=self.api.connect(CLIENT,REDIRECT)['access_token']
        else:self.fail('Could not measure a request burst within one ship minute')
        self.assertEqual(statuses[:120],[200]*120);self.assertEqual(statuses[120],429)
        self.assertEqual(self.api.request('/connect/oauth/revoke','POST',{},token=self.token)[0],200)
        self.assertEqual(self.api.request('/connect/v1/collections/lists/documents',token=self.token)[0],401)
if __name__=='__main__':unittest.main()
