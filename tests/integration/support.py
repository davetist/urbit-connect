"""Private loopback-only real-ship harness. Credentials never enter argv/logs."""
import json
from pathlib import Path
import secrets
import ssl
import urllib.error
import urllib.parse
import urllib.request
import hashlib
import base64
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from targets import TARGETS

ROOT = Path(__file__).resolve().parents[2]
ORIGIN = TARGETS.origin()
CLIENT = 'connect-todo-prototype'
REDIRECT = 'org.example.urbitconnect.todo:/oauth/callback'
SCOPES = 'documents:read documents:write documents:delete'

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs): return None

class API:
    def __init__(self, origin=ORIGIN):
        TARGETS.require_owned()
        self.origin=origin
        self.owner_origin=ORIGIN
        self.opener = urllib.request.build_opener(NoRedirect(), urllib.request.HTTPSHandler(context=ssl.create_default_context(cafile=ROOT/'.work/alpha/tls/ca.crt')))
        private = json.loads((ROOT/'.work/alpha/dev/auth.json').read_text())
        self.cookie = private['cookie']
        self.csrf = None
    def request(self, path, method='GET', data=None, *, owner=False, token=None, headers=None, form=False):
        fields = {}
        if owner:
            fields.update({'Cookie':self.cookie, 'Origin':self.owner_origin})
            if self.csrf: fields['X-Connect-CSRF'] = self.csrf
        if token: fields['Authorization'] = 'Bearer '+token
        if data is not None:
            if form:
                raw = urllib.parse.urlencode(data).encode(); fields['Content-Type']='application/x-www-form-urlencoded'
            elif isinstance(data, bytes):
                raw=data; fields['Content-Type']='application/json'
            else:
                raw=json.dumps(data,ensure_ascii=False,separators=(',',':')).encode();fields['Content-Type']='application/json'
        else: raw=None
        fields.update(headers or {})
        request=urllib.request.Request(self.origin+path,data=raw,headers=fields,method=method)
        try: response=self.opener.open(request,timeout=35)
        except urllib.error.HTTPError as error: response=error
        with response:
            body=response.read()
            try: value=json.loads(body)
            except (ValueError,UnicodeDecodeError): value={'unparsed':True}
            return response.status,value,dict(response.headers)
    def setup(self):
        status,body,_=self.request('/connect/owner/v1/bootstrap',owner=True)
        if status != 200: raise AssertionError(f'owner bootstrap returned HTTP {status}')
        self.csrf=body['csrf']
        status,_,_=self.request('/connect/owner/v1/configure','POST',{'issuer':self.owner_origin+'/connect'},owner=True)
        if status != 200: raise AssertionError(f'owner configuration returned HTTP {status}')
        self.register(CLIENT,REDIRECT)
    def register(self,client,redirect,name='Todo prototype'):
        status,body,_=self.request('/connect/owner/v1/clients','POST',{'id':client,'name':name,'redirectURI':redirect},owner=True)
        if status == 409:
            status,body,_=self.request('/connect/owner/v1/clients',owner=True)
            if status != 200: raise AssertionError(f'client list returned HTTP {status}')
            return next(item for item in body['clients'] if item['id']==client)
        if status != 200: raise AssertionError(f'client registration returned HTTP {status}')
        return body
    def begin(self,client=CLIENT,redirect=REDIRECT,scope=SCOPES,**overrides):
        verifier=secrets.token_urlsafe(32)
        challenge=base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b'=').decode()
        params={'response_type':'code','client_id':client,'redirect_uri':redirect,'scope':scope,'state':secrets.token_urlsafe(32),'code_challenge_method':'S256','code_challenge':challenge}
        params.update(overrides)
        result=self.request('/connect/oauth/authorize?'+urllib.parse.urlencode(params),owner=True)
        return result,params,verifier
    def approve(self,result,decision='approve'):
        status,_,headers=result
        if status != 302: raise AssertionError(f'authorization start returned HTTP {status}')
        location=headers.get('Location',headers.get('location',''))
        request_id=urllib.parse.parse_qs(urllib.parse.urlsplit(location).query)['consent'][0]
        status,body,_=self.request('/connect/owner/v1/consents/'+request_id,'POST',{'decision':decision},owner=True)
        if status != 200: raise AssertionError(f'consent returned HTTP {status}')
        return urllib.parse.parse_qs(urllib.parse.urlsplit(body['redirect']).query)
    def connect(self,client=CLIENT,redirect=REDIRECT,scope=SCOPES):
        result,params,verifier=self.begin(client,redirect,scope)
        callback=self.approve(result)
        if callback['state'][0] != params['state']: raise AssertionError('callback state mismatch')
        status,body,_=self.request('/connect/oauth/token','POST',{'grant_type':'authorization_code','client_id':client,'redirect_uri':redirect,'code':callback['code'][0],'code_verifier':verifier},form=True)
        if status != 200: raise AssertionError(f'token exchange returned HTTP {status}')
        return body
