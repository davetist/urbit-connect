from targets import TARGETS
"""Own a matched fake-ship pair for real EAuth acceptance, separate from app-test history."""
import argparse
import http.cookiejar
import json
from pathlib import Path
import re
import ssl
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from dev_ship import ROOT,MARKER,prepare_state,rpc
from package_desk import checked_command,stage

PRIMARY=ROOT/'.work/alpha/eauth-primary'
PEER=ROOT/'.work/alpha/foreign-peer'
ORIGIN=TARGETS.origin('primary_https')

def stopped(state):
    try:rpc(state,'stop',timeout=100)
    except OSError:pass

def login_primary(context):
    reply=rpc(PRIMARY,'command',command='+code')['output']
    code=re.findall(r'~?[a-z]{6}(?:-[a-z]{6}){3}',reply)[-1].lstrip('~')
    jar=http.cookiejar.CookieJar()
    opener=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar),urllib.request.HTTPSHandler(context=context))
    request=urllib.request.Request(ORIGIN+'/~/login',data=urllib.parse.urlencode({'password':code}).encode(),method='POST')
    with opener.open(request,timeout=30)as response:response.read()
    cookie='; '.join(c.name+'='+c.value for c in jar)
    if not cookie:raise RuntimeError('Dedicated EAuth primary owner login failed')
    private=PRIMARY/'auth.json';private.write_text(json.dumps({'code':code,'cookie':cookie}));private.chmod(0o600)
    headers={'Cookie':cookie,'Origin':ORIGIN}
    with urllib.request.urlopen(urllib.request.Request(ORIGIN+'/connect/owner/v1/bootstrap',headers=headers),context=context,timeout=15)as response:csrf=json.load(response)['csrf']
    headers.update({'Content-Type':'application/json','X-Connect-CSRF':csrf})
    request=urllib.request.Request(ORIGIN+'/connect/owner/v1/configure',data=json.dumps({'issuer':ORIGIN+'/connect'}).encode(),headers=headers,method='POST')
    with urllib.request.urlopen(request,context=context,timeout=15)as response:
        if response.status!=200:raise RuntimeError('Dedicated EAuth primary configuration failed')

def start():
    owned={rpc(ROOT/'.work/alpha/dev','status')['pid']}
    for state in [PRIMARY,PEER]:
        try:owned.add(rpc(state,'status')['pid'])
        except (OSError,RuntimeError):pass
    for port in [TARGETS.port('primary_ames'),TARGETS.port('peer_ames')]:
        result=subprocess.run(['lsof','-t','-iUDP:'+str(port)],capture_output=True,text=True)
        if any(int(pid)not in owned for pid in result.stdout.split()):raise RuntimeError('A foreign process owns a fake-galaxy port')
    stopped(ROOT/'.work/alpha/dev')
    # A peer from an earlier primary cannot be reused as half of a new pair:
    # Ames messaging retains conversation state across process restarts.
    if not(PRIMARY/'zod').exists()and(PEER/'nec').exists():
        prepare_state(PEER);stopped(PEER)
        archive=PEER.with_name('foreign-peer-before-isolated-'+time.strftime('%Y%m%d-%H%M%S'))
        PEER.rename(archive)
    subprocess.run([sys.executable,str(ROOT/'scripts/dev_ship.py'),'start','--state-dir',str(PRIMARY),'--port',str(TARGETS.port('primary_http')),'--ames-port',str(TARGETS.port('primary_ames'))],check=True,capture_output=True)
    subprocess.run([sys.executable,str(ROOT/'scripts/dev_ship.py'),'start','--state-dir',str(PEER),'--port',str(TARGETS.port('peer_http')),'--ames-port',str(TARGETS.port('peer_ames')),'--ship','nec'],check=True,capture_output=True)
    pair={'primaryPierInode':(PRIMARY/'zod/.urb').stat().st_ino,'pierInode':(PEER/'nec/.urb').stat().st_ino}
    marker=PRIMARY/'endpoint-cache.json';cached=json.loads(marker.read_text())if marker.exists()else{}
    if cached and any(cached.get(k)!=v for k,v in pair.items()):raise RuntimeError('EAuth pair identity changed; preserve and recreate both owned fixtures together')
    if not(PRIMARY/'zod/connect').exists():
        checked_command(PRIMARY,'|new-desk %connect');checked_command(PRIMARY,'|mount %connect')
    stage(PRIMARY);checked_command(PRIMARY,'|install our %connect')
    for state,url in [(PRIMARY,ORIGIN),(PEER,TARGETS.origin('peer_https'))]:
        checked_command(state,"|pass [%e %eauth-host ~ '"+url+"']")
    context=ssl.create_default_context(cafile=ROOT/'.work/alpha/tls/ca.crt')
    login_primary(context)
    reply=rpc(PEER,'command',command='+code')['output'];code=re.findall(r'~?[a-z]{6}(?:-[a-z]{6}){3}',reply)[-1].lstrip('~')
    with urllib.request.urlopen(TARGETS.origin('peer_https')+'/~/host',context=context,timeout=15)as response:
        if response.read().decode()!='~nec':raise RuntimeError('Foreign fixture has an unexpected identity')
    private=PEER/'auth.json';private.write_text(json.dumps({'code':code}));private.chmod(0o600)
    if not cached:
        output=rpc(PRIMARY,'command',command='(div (mod now ~m5) (bex 64))')['output']
        elapsed=int(re.findall(r'(?m)~zod:dojo> ([0-9]+)\s*$',output)[-1])
        if not 0<=elapsed<300:raise RuntimeError('Unexpected kernel EAuth cache clock')
        ready=time.monotonic()+301-elapsed
        print('Waiting for the matched pair’s kernel EAuth cache boundary.',flush=True)
        while True:
            remaining=ready-time.monotonic()
            if remaining<=0:break
            time.sleep(min(30,remaining))
        marker.write_text(json.dumps({**pair,'readyAfter':time.time()})+'\n')
    rpc(PRIMARY,'command',command='|hi ~nec',timeout=30)
    print('Matched fake ~zod / ~nec EAuth fixtures ready; normal app fixture remains paused')

def stop():
    stopped(PEER);stopped(PRIMARY)
    subprocess.run([sys.executable,str(ROOT/'scripts/dev_ship.py'),'start'],check=True,capture_output=True)
    print('EAuth pair stopped; normal app fixture restored')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['start','stop']);args=parser.parse_args();start()if args.action=='start'else stop()
