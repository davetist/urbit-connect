import unittest
from support import API,CLIENT
from test_documents import mutation,put

class OwnerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.api=API();cls.api.setup()
        cls.app=cls.api.register(CLIENT,'org.example.urbitconnect.todo:/oauth/callback')
    def test_owner_edits_are_versioned_and_visible_to_app(self):
        tokens=self.api.connect();token=tokens['access_token'];ns=tokens['grant']['namespace']
        op=put();status,first,_=self.api.request('/connect/v1/mutations','POST',mutation(op),token=token);self.assertEqual(status,200)
        change=mutation(put(op['id'],first['revision'],{'title':'Changed on ship'}))
        status,commit,_=self.api.request('/connect/owner/v1/namespaces/'+ns+'/mutations','POST',change,owner=True);self.assertEqual(status,200)
        self.assertNotEqual(commit['revision'],first['revision'])
        status,row,_=self.api.request('/connect/v1/collections/lists/documents/'+op['id'],token=token)
        self.assertEqual(status,200);self.assertEqual(row['data']['title'],'Changed on ship')
        status,_,_=self.api.request('/connect/owner/v1/namespaces/'+ns+'/mutations','POST',change|{'requestId':__import__('uuid').uuid4().__str__()},owner=True)
        self.assertEqual(status,409)
    def test_owner_revoke_keeps_documents(self):
        tokens=self.api.connect();token=tokens['access_token'];grant=tokens['grant']
        op=put();self.assertEqual(self.api.request('/connect/v1/mutations','POST',mutation(op),token=token)[0],200)
        self.assertEqual(self.api.request('/connect/owner/v1/revoke','POST',{'sessionId':grant['sessionId']},owner=True)[0],200)
        self.assertEqual(self.api.request('/connect/v1/identity',token=token)[0],401)
        status,body,_=self.api.request('/connect/owner/v1/namespaces/'+grant['namespace']+'/documents',owner=True)
        self.assertEqual(status,200);self.assertIn(op['id'],[d['id']for d in body['documents']])
    def test_erase_rotates_namespace_and_rejects_old_retry(self):
        self.api.register('connect-erase-test','org.example.connect.erase:/callback')
        tokens=self.api.connect('connect-erase-test','org.example.connect.erase:/callback');token=tokens['access_token'];grant=tokens['grant']
        body=mutation(put());self.assertEqual(self.api.request('/connect/v1/mutations','POST',body,token=token)[0],200)
        path='/connect/owner/v1/namespaces/'+grant['namespace']+'/erase'
        self.assertEqual(self.api.request(path,'POST',{'confirmNamespace':'wrong'},owner=True)[0],400)
        status,result,_=self.api.request(path,'POST',{'confirmNamespace':grant['namespace']},owner=True);self.assertEqual(status,200)
        self.assertNotEqual(result['namespaceEpoch'],grant['namespaceEpoch'])
        self.assertEqual(self.api.request('/connect/v1/mutations','POST',body,token=token)[0],401)
    def test_app_token_cannot_use_owner_routes(self):
        tokens=self.api.connect();token=tokens['access_token'];ns=tokens['grant']['namespace']
        for path,method in [('bootstrap','GET'),('clients','GET'),('sessions','GET'),('revoke','POST'),('restore-epoch','POST'),('namespaces/'+ns+'/mutations','POST'),('namespaces/'+ns+'/erase','POST'),('imports/validate','POST')]:
            status,_,_=self.api.request('/connect/owner/v1/'+path,method,{}if method=='POST'else None,token=token)
            self.assertEqual(status,401)
    def test_import_rejects_malformed_metadata_and_duplicate_targets(self):
        target=self.api.register('connect-import-test','org.example.connect.import:/callback')['namespace']
        doc={'id':put()['id'],'collection':'lists','data':{'x':1},'revision':'1','updatedAt':'2026-10-12T00:00:00Z'}
        source={'issuer':'https://example.invalid/connect','instanceId':'test','ship':'~zod','syncEpoch':'1'}
        envelope={'formatVersion':1,'source':source,'namespace':'source','collections':{'lists':[doc]}}
        import copy
        cases=[]
        for key in source:
            bad=copy.deepcopy(envelope);del bad['source'][key];cases.append(bad)
        for key,value in [('revision','bad'),('updatedAt',None)]:
            bad=copy.deepcopy(envelope);bad['collections']['lists'][0][key]=value;cases.append(bad)
        bad=copy.deepcopy(envelope);bad['collections']['lists'].append(doc);cases.append(bad)
        for bad in cases:
            with self.subTest(invalidEnvelope=cases.index(bad)):
                status,_,_=self.api.request('/connect/owner/v1/imports/validate','POST',{'namespace':target,'mode':'create','export':bad},owner=True)
                self.assertEqual(status,400)
    def test_import_validation_and_apply(self):
        self.api.register('connect-import-test','org.example.connect.import:/callback')
        target=self.api.register('connect-import-test','org.example.connect.import:/callback')['namespace']
        op=put();envelope={'formatVersion':1,'source':{'issuer':'https://example.invalid/connect','instanceId':'test','ship':'~zod','syncEpoch':'1'},'namespace':'source','collections':{'lists':[{'id':op['id'],'collection':'lists','data':op['data'],'revision':'1','updatedAt':'2026-10-12T00:00:00Z'}]}}
        payload={'namespace':target,'mode':'create','export':envelope}
        status,preview,_=self.api.request('/connect/owner/v1/imports/validate','POST',payload,owner=True)
        self.assertEqual(status,200);self.assertEqual(preview['count'],1)
        self.assertEqual(preview['conflicts'],[])
        status,_,_=self.api.request('/connect/owner/v1/imports/apply','POST',{'namespace':target,'mutation':mutation(*preview['operations'])},owner=True)
        self.assertEqual(status,200)
        status,preview,_=self.api.request('/connect/owner/v1/imports/validate','POST',payload,owner=True)
        self.assertEqual(status,200);self.assertEqual(len(preview['conflicts']),1)

if __name__=='__main__':unittest.main()
