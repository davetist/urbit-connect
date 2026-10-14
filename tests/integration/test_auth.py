import unittest
import urllib.parse
from support import API, CLIENT, REDIRECT

class AuthTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.api=API(); cls.api.setup()
    def test_owner_requires_cookie_and_local_authentication(self):
        status,_,_=self.api.request('/connect/owner/v1/bootstrap')
        self.assertEqual(status,401)
    def test_owner_rejects_missing_csrf_and_forged_origin(self):
        for headers in [{'X-Connect-CSRF':''},{'Origin':'https://evil.invalid'}]:
            status,_,_=self.api.request('/connect/owner/v1/configure','POST',{'issuer':'https://evil.invalid/connect'},owner=True,headers=headers)
            self.assertEqual(status,403)
    def test_injected_redirect_and_pkce_downgrade_stay_local(self):
        for overrides in [{'redirect_uri':'evil:/callback'},{'code_challenge_method':'plain'},{'scope':'ships:admin'},{'scope':''}]:
            result,_,_=self.api.begin(**overrides)
            self.assertEqual(result[0],400)
            self.assertNotIn('Location',result[2])
    def test_real_consent_and_single_use_code(self):
        result,params,verifier=self.api.begin()
        callback=self.api.approve(result)
        self.assertEqual(callback['state'][0],params['state'])
        payload={'grant_type':'authorization_code','client_id':CLIENT,'redirect_uri':REDIRECT,'code':callback['code'][0],'code_verifier':verifier}
        status,tokens,_=self.api.request('/connect/oauth/token','POST',payload,form=True)
        self.assertEqual(status,200)
        self.assertIn('access_token',tokens)
        again,_,_=self.api.request('/connect/oauth/token','POST',payload,form=True)
        self.assertEqual(again,400)
    def test_denial_issues_no_code(self):
        result,_,_=self.api.begin()
        callback=self.api.approve(result,'deny')
        self.assertEqual(callback['error'],['access_denied'])
        self.assertNotIn('code',callback)
    def test_identity_and_revoke(self):
        tokens=self.api.connect()
        status,identity,_=self.api.request('/connect/v1/identity',token=tokens['access_token'])
        self.assertEqual(status,200)
        self.assertEqual(identity['account']['ship'],'~zod')
        self.assertEqual(identity['grant']['clientId'],CLIENT)
        status,_,_=self.api.request('/connect/oauth/revoke','POST',{},token=tokens['access_token'])
        self.assertEqual(status,200)
        status,_,_=self.api.request('/connect/v1/identity',token=tokens['access_token'])
        self.assertEqual(status,401)
    def test_refresh_replay_revokes_session(self):
        tokens=self.api.connect()
        payload={'grant_type':'refresh_token','client_id':CLIENT,'refresh_token':tokens['refresh_token']}
        status,rotated,_=self.api.request('/connect/oauth/token','POST',payload,form=True)
        self.assertEqual(status,200)
        status,_,_=self.api.request('/connect/oauth/token','POST',payload,form=True)
        self.assertEqual(status,400)
        status,_,_=self.api.request('/connect/v1/identity',token=rotated['access_token'])
        self.assertEqual(status,401)

if __name__=='__main__': unittest.main()
