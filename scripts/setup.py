from targets import TARGETS
"""Prepare an isolated, checksum-pinned Connect development environment on Apple Silicon."""
import argparse
import hashlib
import http.cookiejar
import json
import os
from pathlib import Path
import platform
import re
import shutil
import ssl
import subprocess
import sys
import tarfile
import urllib.parse
import urllib.request
from dev_ship import ROOT,prepare_state,rpc

CONFIG=json.loads((ROOT/'toolchain.json').read_text())
WORK=TARGETS.work

def command(args,**kwargs):
    return subprocess.run([str(a)for a in args],check=True,text=True,**kwargs)
def digest(path):
    value=hashlib.sha256()
    with path.open('rb')as stream:
        for part in iter(lambda:stream.read(1024*1024),b''):value.update(part)
    return value.hexdigest()
def download(url,path,expected):
    path.parent.mkdir(parents=True,exist_ok=True)
    if path.exists()and digest(path)==expected:return
    temporary=path.with_suffix(path.suffix+'.partial')
    with urllib.request.urlopen(url,timeout=120)as response,temporary.open('wb')as stream:shutil.copyfileobj(response,stream)
    if digest(temporary)!=expected:raise RuntimeError('Checksum mismatch for '+path.name)
    temporary.replace(path)
def extract_binary(archive,destination):
    destination.parent.mkdir(parents=True,exist_ok=True)
    with tarfile.open(archive)as bundle:
        entries=[entry for entry in bundle.getmembers()if Path(entry.name).name==destination.name and entry.isfile()]
        if len(entries)!=1:raise RuntimeError('Archive does not contain exactly one expected binary')
        with bundle.extractfile(entries[0])as source:payload=source.read()
        if destination.exists()and destination.read_bytes()==payload:return
        temporary=destination.with_suffix('.new');temporary.write_bytes(payload);temporary.chmod(0o755);temporary.replace(destination)
def toolchains():
    vere=WORK/'toolchains/vere-4.6.tgz';download(CONFIG['vere']['archiveURL'],vere,CONFIG['vere']['archiveSHA256'])
    binary=ROOT/CONFIG['vere']['localPath']
    if not binary.exists()or digest(binary)!=CONFIG['vere']['sha256']:extract_binary(vere,binary)
    if digest(binary)!=CONFIG['vere']['sha256']:raise RuntimeError('Runtime binary checksum mismatch')
    download(CONFIG['pill']['url'],ROOT/CONFIG['pill']['localPath'],CONFIG['pill']['sha256'])
    caddy=WORK/'toolchains/caddy.tar.gz';download(CONFIG['caddy']['url'],caddy,CONFIG['caddy']['archiveSHA256'])
    extract_binary(caddy,ROOT/CONFIG['caddy']['localPath'])
def dependencies(install):
    for name,package in [('xcodegen','xcodegen'),('certutil','nss')]:
        candidate=Path('/opt/homebrew/opt/nss/bin/certutil')if name=='certutil'else None
        if not shutil.which(name)and not(candidate and candidate.exists()):
            if not install:raise RuntimeError(f'{name} is required; rerun with --install-tools to install {package} through Homebrew')
            command(['brew','install',package])
    command(['xcodebuild','-version'])
    if not shutil.which('node')or not shutil.which('npm'):raise RuntimeError('Node 22.12+ and npm are required for the owner bundle')
def simulator(allow_download=True):
    metadata=WORK/'dev/simulator.json';expected=CONFIG['simulator']
    runtimes=json.loads(command(['xcrun','simctl','list','runtimes','--json'],capture_output=True).stdout)['runtimes']
    matches=[r for r in runtimes if r.get('version')==expected['version']and r.get('buildversion')==expected['build']and r.get('isAvailable')]
    if not matches:
        if not allow_download:raise RuntimeError('Downloaded runtime does not match the pinned version and build')
        print('Downloading the pinned iOS Simulator runtime; allow about 9 GB plus installation space.',flush=True)
        command(['xcodebuild','-downloadPlatform','iOS','-buildVersion',expected['version'],'-architectureVariant','arm64'])
        return simulator(False)
    runtime=matches[0]['identifier']
    if metadata.exists():
        owned=json.loads(metadata.read_text())
        if owned.get('project')!=str(ROOT) or owned.get('fixtureId')!=TARGETS.fixture_id:raise RuntimeError('Simulator marker belongs to a different fixture')
        devices=json.loads(command(['xcrun','simctl','list','devices','--json'],capture_output=True).stdout)['devices']
        if any(d['udid']==owned['id']for group in devices.values()for d in group):return owned['id']
    device='com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro'
    identity=command(['xcrun','simctl','create','Connect Alpha '+TARGETS.fixture_id,device,runtime],capture_output=True).stdout.strip()
    metadata.write_text(json.dumps({'project':str(ROOT),'fixtureId':TARGETS.fixture_id,'id':identity,'name':'Connect Alpha '+TARGETS.fixture_id,'runtime':runtime,'deviceType':device},indent=2)+'\n');metadata.chmod(0o600)
    return identity

def simulator_small():
    metadata=WORK/'dev/simulator-small.json';primary=json.loads((WORK/'dev/simulator.json').read_text())
    devices=json.loads(command(['xcrun','simctl','list','devices','--json'],capture_output=True).stdout)['devices']
    owned=json.loads(metadata.read_text())if metadata.exists()else None
    if owned and (owned.get('project')!=str(ROOT) or owned.get('fixtureId')!=TARGETS.fixture_id):raise RuntimeError('Unowned small Simulator marker')
    current=next((d for group in devices.values()for d in group if owned and d['udid']==owned['id']),None)
    if not current:
        kind='com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation'
        identity=command(['xcrun','simctl','create','Connect Alpha Small '+TARGETS.fixture_id,kind,primary['runtime']],capture_output=True).stdout.strip()
        owned={'project':str(ROOT),'fixtureId':TARGETS.fixture_id,'id':identity,'name':'Connect Alpha Small '+TARGETS.fixture_id,'runtime':primary['runtime'],'deviceType':kind}
        metadata.write_text(json.dumps(owned,indent=2)+'\n');metadata.chmod(0o600)
    if not current or current['state']!='Booted':command(['xcrun','simctl','boot',owned['id']])
    command(['xcrun','simctl','keychain',owned['id'],'add-root-cert',WORK/'tls/ca.crt'])
    return owned['id']

def tls(identity):
    directory=WORK/'tls';directory.mkdir(exist_ok=True,mode=0o700)
    with (WORK/'logs/tls-setup.log').open('w')as log:
        if not(directory/'ca.crt').exists():
            command(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','30','-keyout',directory/'ca.key','-out',directory/'ca.crt','-subj','/CN=Connect Prototype Test CA','-addext','basicConstraints=critical,CA:TRUE','-addext','keyUsage=critical,keyCertSign,cRLSign'],stdout=log,stderr=log)
        command(['openssl','x509','-in',directory/'ca.crt','-checkend','86400','-noout'],stdout=log,stderr=log)
        if not(directory/'server.crt').exists():
            command(['openssl','req','-new','-newkey','rsa:2048','-nodes','-keyout',directory/'server.key','-out',directory/'server.csr','-subj','/CN=localhost'],stdout=log,stderr=log)
            extension=directory/'server.ext';extension.write_text('subjectAltName=DNS:localhost,IP:127.0.0.1\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n')
            command(['openssl','x509','-req','-in',directory/'server.csr','-CA',directory/'ca.crt','-CAkey',directory/'ca.key','-CAcreateserial','-out',directory/'server.crt','-days','30','-extfile',extension],stdout=log,stderr=log)
    with (WORK/'logs/tls-negative-setup.log').open('w')as log:
        if not(directory/'untrusted.crt').exists():
            command(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','30','-keyout',directory/'untrusted.key','-out',directory/'untrusted.crt','-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost'],stdout=log,stderr=log)
        if not(directory/'wrong-host.crt').exists():
            command(['openssl','req','-new','-newkey','rsa:2048','-nodes','-keyout',directory/'wrong-host.key','-out',directory/'wrong-host.csr','-subj','/CN=wrong.invalid'],stdout=log,stderr=log)
            extension=directory/'wrong-host.ext';extension.write_text('subjectAltName=DNS:wrong.invalid\nbasicConstraints=critical,CA:FALSE\nextendedKeyUsage=serverAuth\n')
            command(['openssl','x509','-req','-in',directory/'wrong-host.csr','-CA',directory/'ca.crt','-CAkey',directory/'ca.key','-CAcreateserial','-out',directory/'wrong-host.crt','-days','30','-extfile',extension],stdout=log,stderr=log)
        for certificate in ['server','untrusted','wrong-host']:command(['openssl','x509','-in',directory/(certificate+'.crt'),'-checkend','86400','-noout'],stdout=log,stderr=log)
    for path in directory.glob('*.key'):path.chmod(0o600)
    command(['xcrun','simctl','boot',identity],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)if not any(d['udid']==identity and d['state']=='Booted'for group in json.loads(command(['xcrun','simctl','list','devices','--json'],capture_output=True).stdout)['devices'].values()for d in group)else None
    command(['xcrun','simctl','keychain',identity,'add-root-cert',directory/'ca.crt'])
    profile=WORK/'firefox-profile';profile.mkdir(exist_ok=True,mode=0o700)
    certutil=shutil.which('certutil')or'/opt/homebrew/opt/nss/bin/certutil'
    if not(profile/'cert9.db').exists():command([certutil,'-N','-d','sql:'+str(profile),'--empty-password'])
    command([certutil,'-A','-d','sql:'+str(profile),'-n','Connect Prototype Test CA','-t','C,,','-i',directory/'ca.crt'])
    quote=lambda p:json.dumps(str(p))
    (WORK/'Caddyfile').write_text('{\n admin off\n persist_config off\n auto_https off\n storage file_system {\n  root '+quote(WORK/'caddy-storage')+'\n }\n}\nhttps://localhost:18443, https://127.0.0.1:18443 {\n bind 127.0.0.1\n tls '+quote(directory/'server.crt')+' '+quote(directory/'server.key')+'\n reverse_proxy 127.0.0.1:18432 {\n  header_up Forwarded "proto=https"\n }\n}\n')
    with (WORK/'Caddyfile').open('a')as config:
        config.write('\nhttps://localhost:18447 {\n bind 127.0.0.1\n tls '+quote(directory/'server.crt')+' '+quote(directory/'server.key')+'\n reverse_proxy 127.0.0.1:31336 {\n  header_up Forwarded \"proto=https\"\n }\n}\n')
        config.write('\nhttps://localhost:18448 {\n bind 127.0.0.1\n tls '+quote(directory/'server.crt')+' '+quote(directory/'server.key')+'\n reverse_proxy 127.0.0.1:31334 {\n  header_up Forwarded "proto=https"\n }\n}\n')
        for port,certificate in [(18444,'untrusted'),(18445,'wrong-host')]:
            config.write(f'\nhttps://localhost:{port} {{\n bind 127.0.0.1\n tls '+quote(directory/(certificate+'.crt'))+' '+quote(directory/(certificate+'.key'))+'\n respond "TLS test only" 200\n}\n')

    config_path=WORK/'Caddyfile'
    text=config_path.read_text()
    for original,name in {18443:'https',18432:'http',18447:'peer_https',31336:'peer_http',18448:'primary_https',31334:'primary_http',18444:'untrusted',18445:'wrong_host'}.items():
        text=text.replace(':'+str(original), ':'+str(TARGETS.port(name)))
    config_path.write_text(text)

def login():
    state=WORK/'dev';output=rpc(state,'command',command='+code')['output']
    codes=re.findall(r'~?[a-z]{6}(?:-[a-z]{6}){3}',output)
    if not codes:raise RuntimeError('Could not obtain the fake ship login code; inspect the private runtime log')
    code=codes[-1].lstrip('~');jar=http.cookiejar.CookieJar()
    opener=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar),urllib.request.HTTPSHandler(context=ssl.create_default_context(cafile=WORK/'tls/ca.crt')))
    request=urllib.request.Request(TARGETS.origin()+'/~/login',data=urllib.parse.urlencode({'password':code}).encode(),method='POST')
    with opener.open(request,timeout=30)as response:
        if response.status!=200:raise RuntimeError('Fake ship login did not succeed')
        response.read()
    cookie='; '.join(c.name+'='+c.value for c in jar)
    if not cookie:raise RuntimeError('No owner cookie returned')
    path=state/'auth.json';path.write_text(json.dumps({'code':code,'cookie':cookie}));path.chmod(0o600)

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--install-tools',action='store_true');parser.add_argument('--toolchains-only',action='store_true');args=parser.parse_args()
    if platform.system()!='Darwin'or platform.machine()!='arm64':raise SystemExit('This pinned prototype environment currently targets Apple Silicon macOS')
    TARGETS.initialize();WORK.mkdir(exist_ok=True,mode=0o700);WORK.chmod(0o700);(WORK/'logs').mkdir(exist_ok=True);prepare_state(WORK/'dev')
    dependencies(args.install_tools);toolchains()
    if args.toolchains_only:return
    command([sys.executable,'-m','venv',WORK/'python'])
    command([WORK/'python/bin/pip','install','-r',ROOT/'scripts/requirements.lock'])
    identity=simulator();tls(identity)
    command([sys.executable,ROOT/'scripts/dev_ship.py','start'])
    state=WORK/'dev'
    if not(state/'zod/connect').exists():
        rpc(state,'command',command='|new-desk %connect',timeout=120);rpc(state,'command',command='|mount %connect',timeout=120)
    command(['npm','ci','--prefix',ROOT/'web']);command(['npm','--prefix',ROOT/'web','run','build']);command([sys.executable,ROOT/'scripts/bundle_web.py'])
    command([sys.executable,ROOT/'scripts/package_desk.py'])
    rpc(state,'command',command='|install our %connect',timeout=120)
    command([sys.executable,ROOT/'scripts/dev_proxy.py','start'])
    login()
    sys.path.insert(0,str(ROOT/'tests/integration'))
    from support import API
    API().setup()
    command([ROOT/'web/node_modules/.bin/playwright','install','firefox','chromium','webkit'])
    command(['xcodegen','generate','--spec',ROOT/'examples/ios-todo/project.yml'])
    print('Ready:',TARGETS.origin()+'/apps/connect/ ; use the dedicated alpha Simulator. Credentials remain private in .work/alpha/dev/auth.json.')
if __name__=='__main__':main()
