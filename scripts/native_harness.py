from targets import TARGETS
"""Private, loopback-only native acceptance controls. Never bundled with the product."""
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import json
from pathlib import Path
import secrets
import ssl
import subprocess
import sys
import threading
import urllib.parse
import base64
import hashlib
import plistlib
import sqlite3
import uuid
import os
from dev_ship import ROOT,rpc
sys.path.insert(0,str(ROOT/'tests/integration'))
from support import API,CLIENT,REDIRECT

def load_authorization_path(value,origin):
    target=urllib.parse.urlsplit(value);params=urllib.parse.parse_qs(target.query)
    if target.scheme!='https' or target.netloc!=urllib.parse.urlsplit(origin).netloc or target.path!='/connect/oauth/authorize' or target.fragment or params.get('client_id')!=['connect-load-test']:
        raise ValueError('Invalid test authorization target')
    return target.path+'?'+target.query

def owner_load_document(api,space,id):
    offset=0
    for _ in range(10):
        status,body,_=api.request('/connect/owner/v1/namespaces/'+space+'/documents?limit=100&page='+str(offset),owner=True)
        if status!=200:raise RuntimeError('Load fixture cannot be read')
        found=next((row for row in body['documents']if row['collection']=='lists' and row['id']==id),None)
        if found is not None:return found
        page=body['nextPage']
        if page is None:break
        if not isinstance(page,str)or not page.isascii()or not page.isdecimal()or not offset<int(page)<=1000:raise ValueError('Invalid bounded load fixture pagination')
        offset=int(page)
    raise RuntimeError('Load fixture document is missing')

def teardown(server,metadata,recover,capacity):
    try:capacity()
    finally:
        try:server.shutdown()
        finally:
            try:server.server_close()
            finally:
                try:metadata.unlink(missing_ok=True)
                finally:recover()

@contextmanager
def running(simulator, api_override=None,run_id=None):
    TARGETS.require_owned()
    markers = [json.loads(path.read_text()) for path in (TARGETS.state('dev')).glob('simulator*.json')]
    if not any(m.get('id') == simulator and m.get('project') == str(ROOT) and m.get('fixtureId') == TARGETS.fixture_id for m in markers): raise ValueError('Refusing an unowned native target')
    devices = json.loads(subprocess.check_output(['xcrun','simctl','list','devices','--json']))['devices']
    if not any(d['udid'] == simulator and d['name'] in ['Connect Alpha ' + TARGETS.fixture_id, 'Connect Alpha Small ' + TARGETS.fixture_id] for group in devices.values() for d in group): raise ValueError('Simulator no longer matches its ownership marker')
    real_target = api_override is not None
    api=api_override or API(f"http://127.0.0.1:{TARGETS.port('http')}");api.setup();namespace=api.register(CLIENT,REDIRECT)['namespace']
    secret=secrets.token_urlsafe(32);measurement_run=run_id or str(uuid.uuid4())
    capacity_backup = TARGETS.work / 'native-tests/capacity-rows.json'
    def local_database():
        container = Path(subprocess.check_output(['xcrun','simctl','get_app_container',simulator,'org.example.urbitconnect.todo','data'],text=True).strip())
        directory = container / 'Library/Application Support/UrbitConnect'
        selected = directory / ('selected-' + hashlib.sha256(CLIENT.encode()).hexdigest() + '.txt')
        key = selected.read_text()
        if len(key) != 64 or any(c not in '0123456789abcdef' for c in key): raise ValueError('Invalid test account selection')
        path = directory / (key + '.sqlite')
        if path.is_symlink() or not path.resolve().is_relative_to(container.resolve()): raise ValueError('Invalid test database path')
        return path
    def local_stats():
        path = local_database(); connection = sqlite3.connect('file:' + str(path) + '?mode=ro',uri=True)
        try:
            rows = [json.loads(row[0]) for row in connection.execute('SELECT wire FROM outbox ORDER BY rowid')]
            return {'schema': connection.execute('PRAGMA user_version').fetchone()[0], 'pendingCount': len(rows), 'requestHashes': [hashlib.sha256(base64.b64decode(row['body'])).hexdigest() for row in rows], 'mutationIDsSHA256':hashlib.sha256(json.dumps([row['id'] for row in rows]).encode()).hexdigest(), 'databaseBytes':path.stat().st_size, 'walBytes':Path(str(path)+'-wal').stat().st_size if Path(str(path)+'-wal').exists() else 0}
        finally: connection.close()
    def restore_capacity():
        if not capacity_backup.exists(): return
        saved = json.loads(capacity_backup.read_text()); path = local_database()
        if saved['fixtureId'] != TARGETS.fixture_id or saved['database'] != str(path): raise ValueError('Wrong capacity backup ownership')
        connection = sqlite3.connect(path)
        try:
            with connection:
                connection.execute('DELETE FROM outbox')
                connection.executemany('INSERT INTO outbox(id,created,wire,request_bytes) VALUES(?,?,?,?)',[(row[0],row[1],base64.b64decode(row[2]),row[3]) for row in saved['rows']])
        finally: connection.close()
        capacity_backup.unlink()
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args):pass
        def do_POST(self):
            if self.path!='/'or not secrets.compare_digest(self.headers.get('Authorization',''),'Bearer '+secret):self.send_error(403);return
            length=int(self.headers.get('Content-Length','0'))
            if not 0<length<262144:self.send_error(413);return
            try:
                value=json.loads(self.rfile.read(length));action=value['action']
                status,bootstrap,_=api.request('/connect/owner/v1/bootstrap',owner=True)
                if status!=200:raise RuntimeError('Owner context unavailable')
                api.csrf=bootstrap['csrf']
                if action=='documents':
                    status,result,_=api.request('/connect/owner/v1/namespaces/'+namespace+'/documents',owner=True)
                elif action=='mutate':
                    status,result,_=api.request('/connect/owner/v1/namespaces/'+namespace+'/mutations','POST',value['mutation'],owner=True)
                elif action=='reset':
                    status,result,_=api.request('/connect/owner/v1/namespaces/'+namespace+'/erase','POST',{'confirmNamespace':namespace},owner=True)
                elif action=='revoke':
                    status,result,_=api.request('/connect/owner/v1/revoke','POST',{'clientId':CLIENT},owner=True)
                elif action=='proxy-off':
                    if real_target: api.ingress(False)
                    else: rpc(ROOT/'.work/alpha/proxy','stop')
                    status,result=200,{'offline':True}
                elif action=='proxy-on':
                    if real_target: api.ingress(True)
                    else: subprocess.run([sys.executable,str(ROOT/'scripts/dev_proxy.py'),'start'],check=True,capture_output=True)
                    status,result=200,{'offline':False}
                elif action=='desk-update' and real_target:
                    status,result=200,api.update_desk()
                elif action=='network-profile' and real_target:
                    status,result=200,api.packet_profile(value['profile'])
                elif action=='appearance':
                    style=value['style']
                    if style not in ('light','dark'):raise ValueError('Invalid appearance')
                    subprocess.run(['xcrun','simctl','ui',simulator,'appearance',style],check=True,capture_output=True)
                    status,result=200,{'appearance':style}
                elif action in ('fresh-baseline-app','install-app-update'):
                    bundle = TARGETS.work / ('baseline-Todo.app' if action == 'fresh-baseline-app' else 'DerivedData-Todo/Build/Products/Debug-iphonesimulator/ConnectTodo.app')
                    if bundle.is_symlink() or plistlib.loads((bundle/'Info.plist').read_bytes())['CFBundleIdentifier'] != 'org.example.urbitconnect.todo': raise ValueError('Wrong test app bundle')
                    if action == 'fresh-baseline-app':
                        marker = json.loads((TARGETS.work/'baseline-Todo.json').read_text())
                        entries = {p.relative_to(bundle).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in bundle.rglob('*') if p.is_file()}
                        if marker['fixtureId'] != TARGETS.fixture_id or marker['project'] != str(ROOT) or marker['bundleSHA256'] != hashlib.sha256(json.dumps(entries,sort_keys=True).encode()).hexdigest(): raise ValueError('Baseline app ownership or hash mismatch')
                        framework_path = TARGETS.work / 'baseline-runtime/PackageFrameworks'
                        entries = {p.relative_to(framework_path).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in framework_path.rglob('*') if p.is_file()}
                        if marker.get('runtimeFrameworkPath') != str(framework_path) or not entries or marker.get('runtimeFrameworksSHA256') != hashlib.sha256(json.dumps(entries,sort_keys=True).encode()).hexdigest(): raise ValueError('Baseline runtime ownership or hash mismatch')
                        subprocess.run(['xcrun','simctl','uninstall',simulator,'org.example.urbitconnect.todo'],capture_output=True)
                    subprocess.run(['xcrun','simctl','install',simulator,str(bundle)],check=True,capture_output=True)
                    status,result=200,{'installed':True,'preservedInstall':action=='install-app-update'}
                    if action == 'fresh-baseline-app':
                        # XCUIApplication.launch installs Xcode's current product first.
                        # Launch the preserved baseline through simctl, then attach by ID.
                        environment = dict(os.environ); environment['SIMCTL_CHILD_DYLD_FRAMEWORK_PATH'] = str(framework_path)
                        subprocess.run(['xcrun','simctl','launch',simulator,'org.example.urbitconnect.todo'],check=True,capture_output=True,env=environment)
                        result['baselineLaunched'] = True
                elif action=='local-storage': status,result=200,local_stats()
                elif action=='fill-outbox-capacity':
                    # Only while the test app is terminated and its proxy is down.
                    import socket
                    try:
                        with socket.create_connection(('127.0.0.1',TARGETS.port('https')),timeout=1): raise ValueError('Capacity injection requires isolated offline ingress')
                    except OSError: pass
                    path = local_database(); connection = sqlite3.connect(path)
                    try:
                        rows = list(connection.execute('SELECT id,created,wire,request_bytes FROM outbox ORDER BY rowid'))
                        if len(rows) != 1 or capacity_backup.exists(): raise ValueError('Capacity fixture requires one backed-up mutation')
                        capacity_backup.write_text(json.dumps({'fixtureId':TARGETS.fixture_id,'database':str(path),'rows':[(r[0],r[1],base64.b64encode(r[2]).decode(),r[3]) for r in rows]})); capacity_backup.chmod(0o600)
                        with connection:
                            for _ in range(999):
                                wire = json.loads(rows[0][2]); wire['id'] = str(uuid.uuid4())
                                body = json.loads(base64.b64decode(wire['body'])); body['requestId'] = wire['id']
                                request = json.dumps(body,separators=(',',':')).encode();wire['body'] = base64.b64encode(request).decode()
                                connection.execute('INSERT INTO outbox(id,created,wire,request_bytes) VALUES(?,?,?,?)',(wire['id'],rows[0][1],json.dumps(wire,separators=(',',':')).encode(),len(request)))
                    finally: connection.close()
                    status,result=200,local_stats()
                elif action=='restore-outbox-capacity': restore_capacity();status,result=200,local_stats()
                elif action=='record-app-update':
                    before,after = value['before'],value['after']
                    if before['schema'] != 1 or after['schema'] != 2 or before['pendingCount'] != 1 or after['pendingCount'] != 1 or before['requestHashes'] != after['requestHashes'] or before['mutationIDsSHA256'] != after['mutationIDsSHA256']: raise ValueError('App update did not preserve queued requests')
                    baseline = json.loads((TARGETS.work/'baseline-Todo.json').read_text())
                    report = {'passed':True,'fixtureId':TARGETS.fixture_id,'simulator':simulator,'baselineBundleSHA256':baseline['bundleSHA256'],'baselineRuntimeSHA256':baseline['runtimeFrameworksSHA256'],'before':before,'after':after,'uninstalledBetweenVersions':False,'retainedPairing':True,'capacityRejectPreservedInput':True,'catchUpEffects':1}
                    (ROOT/'artifacts/alpha/app-update.json').write_text(json.dumps(report,indent=2)+'\n')
                    status,result=200,{'recorded':True}
                elif action=='seed-load':
                    from test_documents import mutation,put
                    count=value['count']
                    if type(count)is not int or not 0<=count<=1000:raise ValueError('Invalid bounded fixture count')
                    space=api.register('connect-load-test','org.example.connect.load:/callback','Load tests')['namespace']
                    status,_,_=api.request('/connect/owner/v1/namespaces/'+space+'/erase','POST',{'confirmNamespace':space},owner=True)
                    if status!=200:raise RuntimeError('Fixture erase failed')
                    for offset in range(0,count,32):
                        status,_,_=api.request('/connect/owner/v1/namespaces/'+space+'/mutations','POST',mutation(*[put(data={'title':'Native SDK load fixture'})for _ in range(min(32,count-offset))]),owner=True)
                        if status!=200:raise RuntimeError('Fixture batch failed')
                    status,result=200,{'count':count}
                elif action=='authorize-load':
                    path=load_authorization_path(value['url'],api.owner_origin if real_target else TARGETS.origin())
                    response=api.request(path,owner=True);callback=api.approve(response)
                    status,result=200,{'callback':'org.example.connect.load:/callback?'+urllib.parse.urlencode({k:v[0]for k,v in callback.items()})}
                elif action=='mutate-load' and real_target:
                    from test_documents import mutation,put
                    id=str(uuid.UUID(value['id']))
                    space=api.register('connect-load-test','org.example.connect.load:/callback','Load tests')['namespace']
                    current=owner_load_document(api,space,id)
                    status,result,_=api.request('/connect/owner/v1/namespaces/'+space+'/mutations','POST',mutation(put(document=id,expected=current['revision'],data={'title':'Remote visibility check'})),owner=True)
                elif action=='record-sdk-load':
                    seconds=value['seconds']
                    if not isinstance(seconds,(int,float))or not 0<seconds<120:raise ValueError('Invalid measurement')
                    documents=value['documents']
                    if type(documents)is not int or documents!=1000:raise ValueError('Incomplete SDK hydration measurement')
                    report={'documents':documents,'snapshotAndSQLiteSeconds':seconds,'nativeSimulator':True,'measurementRunID':measurement_run}
                    if real_target:
                        visibility=value['visibilitySeconds']
                        if not 0<seconds<30 or not isinstance(visibility,(int,float)) or not 0<visibility<5:raise ValueError('Real native measurement exceeded its gate')
                        profile=api.packet_status()
                        if profile['profile']!='100ms-1percent':raise ValueError('Real SDK profile did not match the measurement')
                        report.update(status='measured',passed=False,realShip=True,normalSystemTLS=True,automaticForegroundObservationSeconds=visibility,networkProfile=profile)
                    path=ROOT/('artifacts/alpha/real-sdk-load.json'if real_target else'artifacts/alpha/sdk-load.json');path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(report,indent=2)+'\n')
                    status,result=200,{'recorded':True}
                else:status,result=400,{'error':'Unknown acceptance action'}
                raw=json.dumps(result).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
            except Exception as error:
                # Never serialize request headers, response tokens, or arbitrary exception text.
                import traceback
                diagnostic = TARGETS.work / 'native-tests/control-failure.txt'
                diagnostic.parent.mkdir(parents=True,exist_ok=True)
                diagnostic.write_text(traceback.format_exc())
                if isinstance(error, subprocess.CalledProcessError):
                    with diagnostic.open('a') as output:
                        for content in [error.stdout, error.stderr]:
                            if content: output.write(content.decode(errors='replace') if isinstance(content,bytes) else content)
                diagnostic.chmod(0o600)
                self.send_error(500,'Acceptance control failed: '+type(error).__name__)
    server=ThreadingHTTPServer(('127.0.0.1',TARGETS.port('control')),Handler)
    context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(ROOT/'.work/alpha/tls/server.crt',ROOT/'.work/alpha/tls/server.key');server.socket=context.wrap_socket(server.socket,server_side=True)
    metadata=ROOT/'.work/alpha/native-tests/control.json';metadata.parent.mkdir(parents=True,exist_ok=True);metadata.write_text(json.dumps({'url':TARGETS.origin('control')+'/','token':secret}));metadata.chmod(0o600)
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    try:yield metadata
    finally:
        def capacity():
            if capacity_backup.exists():
                subprocess.run(['xcrun','simctl','terminate',simulator,'org.example.urbitconnect.todo'],capture_output=True)
                restore_capacity()
        def recover():
            if real_target:
                try:api.stop_packet_fixture()
                finally:api.ingress(True)
            else:subprocess.run([sys.executable,str(ROOT/'scripts/dev_proxy.py'),'start'],check=True,capture_output=True)
        teardown(server,metadata,recover,capacity)
