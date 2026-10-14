from targets import TARGETS
"""Measure bounded real-ship reads, writes, and reconnect snapshots; never a production benchmark."""
import json
import math
import platform
from pathlib import Path
import statistics
import subprocess
import sys
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tests/integration'))
from support import API,ROOT
from test_documents import mutation,put
sys.path.insert(0,str(ROOT/'scripts'));from dev_ship import rpc

def distribution(values):
    values=sorted(values)
    return {'count':len(values),'p50Ms':round(statistics.median(values)*1000,2),'p95Ms':round(values[math.ceil(len(values)*.95)-1]*1000,2),'maxMs':round(max(values)*1000,2)}
def measure():
    api=API();api.setup();client='connect-load-test';redirect='org.example.connect.load:/callback';space=api.register(client,redirect,'Load tests')['namespace'];reports=[]
    pid=rpc(ROOT/'.work/alpha/dev','status')['pid']
    def resource():
        processes=[tuple(map(int,line.split()))for line in subprocess.check_output(['ps','-axo','pid=,ppid=,rss='],text=True).splitlines()if line.strip()]
        owned={pid}
        while True:
            descendants=owned|{child for child,parent,_ in processes if parent in owned}
            if descendants==owned:break
            owned=descendants
        rss=sum(resident for child,_,resident in processes if child in owned)*1024
        log=ROOT/'.work/alpha/dev/zod/.urb/log'
        disk=int(subprocess.check_output(['du','-sk',str(log)],text=True).split()[0])*1024
        files=[path for path in log.rglob('*')if path.is_file()]
        return {'rssBytes':rss,'runtimeProcessCount':len(owned),'allocatedEventLogBytes':disk,
                'databaseFileBytes':sum(path.stat().st_size for path in files if path.name=='data.mdb'),
                'imageFileBytes':sum(path.stat().st_size for path in files if path.name=='image.bin')}
    for count in [100,500,1000]:
        status,_,_=api.request('/connect/owner/v1/namespaces/'+space+'/erase','POST',{'confirmNamespace':space},owner=True);assert status==200
        token=api.connect(client,redirect)['access_token'];before=resource();ids=[]
        for start in range(0,count,32):
            operations=[put(data={'title':'Benchmark item','completed':False})for _ in range(min(32,count-start))];ids.extend(op['id']for op in operations)
            status,_,_=api.request('/connect/v1/mutations','POST',mutation(*operations),token=token);assert status==200
        reads=[];writes=[]
        for id in ids[:20]:
            start=time.perf_counter();status,row,_=api.request('/connect/v1/collections/lists/documents/'+id,token=token);reads.append(time.perf_counter()-start);assert status==200
            start=time.perf_counter();status,_,_=api.request('/connect/v1/mutations','POST',mutation(put(id,row['revision'],{'title':'Updated item','completed':True})),token=token);writes.append(time.perf_counter()-start);assert status==200
        reconnect=[]
        for _ in range(3):
            start=time.perf_counter();status,page,_=api.request('/connect/v1/snapshots','POST',{},token=token);assert status==200;seen=[]
            while True:
                seen.extend(d['id']for d in page['documents'])
                if page['nextPage']is None:break
                status,page,_=api.request('/connect/v1/snapshots/'+page['snapshotId']+'?page='+page['nextPage'],token=token);assert status==200
            reconnect.append(time.perf_counter()-start);assert len(seen)==count and len(set(seen))==count
        reports.append({'documents':count,'read':distribution(reads),'write':distribution(writes),'snapshotReconnect':distribution(reconnect),'before':before,'after':resource()})
    report={'hardware':subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip(),'memoryBytes':int(subprocess.check_output(['sysctl','-n','hw.memsize'],text=True)),'os':platform.platform(),'runtime':'Vere 4.6 / kernel 408','transport':'loopback HTTPS; Python snapshot download, not Swift cache installation',
            'memoryMeasurement':'Sum of RSS for the owned Vere parent and descendants; shared pages may be counted more than once.',
            'diskMeasurement':'Filesystem allocated bytes for .urb/log, with apparent data.mdb and image.bin sizes separately. This is not logical record size; reused/preallocated database pages can produce zero short-run file growth.',
            'results':reports}
    target=ROOT/'artifacts/alpha/load.json';target.parent.mkdir(parents=True,exist_ok=True);target.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    if any(r['read']['p95Ms']>=1000 or r['write']['p95Ms']>=1000 or r['snapshotReconnect']['maxMs']>=10000 for r in reports):raise AssertionError('Prototype latency target failed')
    print('PASS: bounded HTTP load targets; SDK reconnect timing is separately required')
if __name__=='__main__':measure()
