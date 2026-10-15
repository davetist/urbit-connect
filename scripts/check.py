from targets import TARGETS
"""Run the complete prototype acceptance checks sequentially, rejecting skipped/zero test suites."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import ssl
import subprocess
import sys
import time
import urllib.request
from dev_ship import ROOT,rpc

REPORTS=[]
def run(name,command,count=None):
    print('CHECK:',name,flush=True);start=time.monotonic()
    result=subprocess.run([str(x)for x in command],cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    output=result.stdout;path=ROOT/'.work/alpha/logs'/('check-'+name+'.log');path.parent.mkdir(parents=True,exist_ok=True);path.write_text(output);path.chmod(0o600)
    matches=re.findall(count,output)if count else []
    passed=result.returncode==0 and(not count or any(int(n)>0 for n in matches))
    if re.search(r'(?m)(?:^|\s)[1-9][0-9]* skipped\b|ℹ skipped [1-9]',output):passed=False
    REPORTS.append({'check':name,'passed':passed,'seconds':round(time.monotonic()-start,2),'cases':int(matches[-1])if matches else None})
    if not passed:raise RuntimeError(name+' failed; inspect its private log '+str(path))
    print('PASS:',name,('('+matches[-1]+' cases)')if matches else '',flush=True)

def environment():
    TARGETS.require_owned()
    config=json.loads((ROOT/'toolchain.json').read_text())
    for name in ['vere','pill']:
        path=ROOT/config[name]['localPath']
        if hashlib.sha256(path.read_bytes()).hexdigest()!=config[name]['sha256']:raise AssertionError(name+' digest mismatch')
    if not rpc(ROOT/'.work/alpha/dev','status')['ready']:raise AssertionError('Owned fake ship is not ready')
    context=ssl.create_default_context(cafile=ROOT/'.work/alpha/tls/ca.crt')
    with urllib.request.urlopen(TARGETS.origin()+'/connect/v1/info',context=context,timeout=10)as response:info=json.load(response)
    if not info['development']or info['protocolVersion']!=1:raise AssertionError('Refusing non-development or incompatible endpoint')
    for port in [TARGETS.port('untrusted'),TARGETS.port('wrong_host')]:
        try:urllib.request.urlopen(f'https://localhost:{port}/',context=context,timeout=10)
        except urllib.error.URLError as error:
            if not isinstance(error.reason,ssl.SSLCertVerificationError):raise
        else:raise AssertionError('Invalid certificate accepted')
    run('tooling',[sys.executable,'-m','unittest','discover','-s','tests/tooling','-v'],r'Ran (\d+) tests?')
    run('xcode',['xcodebuild','-version'])
    print('PASS: pinned runtime/pill, owned fake endpoint, normal TLS and both negative certificate fixtures')

def prepare_integration():
    sys.path.insert(0,str(ROOT/'tests/integration'));from support import API
    api=API();api.setup()
    status,info,_=api.request('/connect/v1/info')
    if status!=200 or not info.get('development'):raise RuntimeError('Only the owned fake ship may be reset')
    status,body,_=api.request('/connect/owner/v1/clients',owner=True);assert status==200
    for client in body['clients']:
        status,_,_=api.request('/connect/owner/v1/revoke','POST',{'clientId':client['id']},owner=True);assert status==200

def seed_browser():
    sys.path.insert(0,str(ROOT/'tests/integration'));from support import API,CLIENT,REDIRECT
    from test_documents import mutation,put
    api=API();api.setup();api.register('connect-erase-test','org.example.connect.erase:/callback');namespace=api.register(CLIENT,REDIRECT)['namespace']
    status,_,_=api.request('/connect/owner/v1/namespaces/'+namespace+'/erase','POST',{'confirmNamespace':namespace},owner=True);assert status==200
    status,_,_=api.request('/connect/owner/v1/namespaces/'+namespace+'/mutations','POST',mutation(put(data={'schemaVersion':1,'title':'Personal','tasks':[]})),owner=True);assert status==200

def prepare_expired_consent():
    import urllib.parse
    sys.path.insert(0,str(ROOT/'tests/integration'));from support import API
    api=API();api.setup();client='connect-import-test';redirect='org.example.connect.import:/callback';api.register(client,redirect)
    (status,_,headers),_,_=api.begin(client,redirect)
    if status!=302:raise RuntimeError('Could not prepare consent-expiry fixture')
    consent=urllib.parse.parse_qs(urllib.parse.urlsplit(headers.get('Location',headers.get('location',''))).query)['consent'][0]
    if api.request('/connect/owner/v1/consents/'+consent,owner=True)[0]!=200:raise RuntimeError('Consent fixture was not initially active')
    target=ROOT/'.work/alpha/dev/expired-consent.json';target.write_text(json.dumps({'consent':consent,'readyAfter':time.time()+302}));target.chmod(0o600)

def evidence():
    secrets=[]
    for private in (TARGETS.work).glob('*/auth.json'):
        values=json.loads(private.read_text());secrets.extend(v.encode()for v in values.values()if isinstance(v,str)and len(v)>12)
        secrets.extend(part.split('=',1)[1].encode()for part in values.get('cookie','').split('; ')if'='in part)
    scanned=0
    for path in(ROOT/'artifacts/alpha').rglob('*'):
        if not path.is_file()or path.suffix.lower()not in ['.json','.txt','.md','.csv','.html']:continue
        raw=path.read_bytes();scanned+=1
        if any(secret in raw for secret in secrets)or b'-----BEGIN PRIVATE KEY-----'in raw or b'-----BEGIN RSA PRIVATE KEY-----'in raw:raise AssertionError('Credential material in acceptance artifact: '+path.name)
    print('PASS: reviewed text evidence contains no known private credentials;',scanned,'files scanned')

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--all',action='store_true');parser.add_argument('--suite',choices=['environment','protocol','hoon','integration','web','sdk','ios','ios-small','reliability','load','package','evidence']);args=parser.parse_args()
    TARGETS.require_owned()
    names=['environment','protocol','web-build','hoon','integration','web','sdk','ios','ios-small','reliability','load','package','evidence']if args.all else[args.suite or'environment']
    try:
        for name in names:
            if name=='environment':environment()
            elif name=='protocol':
                run('protocol-fixtures',[sys.executable,'scripts/protocol_fixtures.py','--check'])
                run('protocol-schema',[ROOT/'.work/alpha/python/bin/python','scripts/test_protocol.py'],r'(\d+) schema fixtures')
            elif name=='web-build':
                run('web-typecheck',['npm','--prefix','web','run','typecheck'])
                run('web-codec',['npm','--prefix','web','test'],r'ℹ tests (\d+)')
                run('web-build',['npm','--prefix','web','run','build'])
                run('web-bundle',[sys.executable,'scripts/bundle_web.py'])
                run('desk-stage',[sys.executable,'scripts/package_desk.py'])
            elif name=='hoon':run('hoon',[sys.executable,'scripts/test_hoon.py','--suite','state,auth,store,limits,codec,json,fixtures,http,entry,policy,integrations'],r'PASS: (\d+) executed Hoon tests')
            elif name=='integration':
                prepare_integration();run('integration',[sys.executable,'scripts/test_integration.py'],r'Ran (\d+) tests?')
            elif name=='web':
                seed_browser();prepare_expired_consent();run('browser-owner',[sys.executable,'scripts/browser_test.py','--spec','consent.spec.ts,management.spec.ts,races.spec.ts,editor-boundary.spec.ts,alpha-manager.spec.ts,resource-management.spec.ts'],r'\"expected\": (\d+)')
                try:
                    run('foreign-peer',[sys.executable,'scripts/foreign_peer.py','start'])
                    run('browser-eauth',[sys.executable,'scripts/browser_test.py','--spec','eauth.spec.ts'],r'\"expected\": (\d+)')
                finally:run('foreign-peer-stop',[sys.executable,'scripts/foreign_peer.py','stop'])
                run('browser-expiry',[sys.executable,'scripts/browser_test.py','--spec','expiry.spec.ts'],r'\"expected\": (\d+)')
            elif name=='sdk':
                run('sdk',['swift','test','--package-path','sdk/swift'],r'Test run with (\d+) tests? in .* passed')
                import release_check
                # A source dependency can leave an old consumer test object with
                # stale Swift actor dispatch offsets. Bind its build cache to all
                # SDK/root-package/consumer inputs, as a fresh consumer build does.
                inputs={group:release_check.tree(group)['sha256'] for group in ['sdk/swift','Package.swift','tests/consumers/swift']}
                build=hashlib.sha256(json.dumps(inputs,sort_keys=True).encode()).hexdigest()[:16]
                run('sdk-public-consumer',['swift','test','--package-path','tests/consumers/swift','--scratch-path',TARGETS.work/('consumer-'+build)],r'Test run with (\d+) tests? in .* passed')
            elif name=='ios':run('ios',[sys.executable,'scripts/ios_test.py','--suite','all'],r'"totalTestCount": (\d+)')
            elif name=='ios-small':run('ios-small',[sys.executable,'scripts/ios_test.py','--suite','ui','--small'],r'\"totalTestCount\": (\d+)')
            elif name=='reliability':
                run('reload-retry',[sys.executable,'scripts/reload_rehearsal.py'])
                run('restore-files',[sys.executable,'scripts/restore_rehearsal.py'])
            elif name=='load':run('load',[sys.executable,'scripts/benchmark.py'])
            elif name=='package':run('package',[sys.executable,'scripts/package_desk.py','--verify-install'])
            elif name=='evidence':evidence()
    finally:
        import release_check
        target=ROOT/'artifacts/alpha/checks.json';target.parent.mkdir(parents=True,exist_ok=True);target.write_text(json.dumps({'scope':names,'checks':REPORTS,'fixtureId':TARGETS.fixture_id,'source':{group:release_check.tree(group) for group in release_check.SOURCE_GROUPS},'recordedAt':time.strftime('%Y-%m-%dT%H:%M:%S%z')},indent=2)+'\n')
    print('All requested checks passed. Inspect the acceptance checklist for separate visual/manual requirements.')
if __name__=='__main__':main()
