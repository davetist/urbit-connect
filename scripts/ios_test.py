from targets import TARGETS
"""Run native iOS tests with private logs and sanitized completion evidence."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from contextlib import ExitStack
from native_harness import running
ROOT=Path(__file__).resolve().parents[1]

def validate_real_sdk_evidence(measured,result,run_id):
    if (result.get('result')!='Passed' or result.get('totalTestCount')!=1 or result.get('passedTests')!=1
            or any(result.get(name)!=0 for name in ['failedTests','skippedTests','expectedFailures'])
            or measured.get('status')!='measured' or measured.get('passed')is not False
            or measured.get('measurementRunID')!=run_id or measured.get('documents')!=1000
            or measured.get('realShip')is not True or measured.get('normalSystemTLS')is not True
            or measured.get('networkProfile',{}).get('profile')!='100ms-1percent'):
        raise ValueError('Real SDK evidence did not match this complete passing native run')
    for field,limit in [('snapshotAndSQLiteSeconds',30),('automaticForegroundObservationSeconds',5)]:
        value=measured.get(field)
        if type(value)not in (int,float)or not 0<value<limit:raise ValueError('Real SDK measurement exceeded its gate')

def simulator_id(small=False):
    if small:
        from setup import simulator_small
        simulator_small()
    marker=json.loads((ROOT/('.work/alpha/dev/simulator-small.json'if small else'.work/alpha/dev/simulator.json')).read_text())
    if marker.get('project')!=str(ROOT) or marker.get('fixtureId')!=TARGETS.fixture_id:raise RuntimeError('Unowned Simulator metadata')
    expected_name = ('Connect Alpha Small ' if small else 'Connect Alpha ') + TARGETS.fixture_id
    if marker.get('name') != expected_name:raise RuntimeError('Wrong fixture Simulator name')
    devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','--json'],text=True))['devices']
    if not any(d['udid']==marker['id'] and d['name']==expected_name for group in devices.values() for d in group):raise RuntimeError('Simulator identity does not match the owned marker')
    return marker['id']

def run(suite,only=None,small=False,real=False):
    TARGETS.require_owned()
    real_test = 'ConnectTodoUITests/ConnectTodoUITests/testRealShipWorkflowAndCompatibleDeskUpdate'
    if real:
        real_sdk='ConnectTodoTests/LiveSDKTests'
        if small or suite not in ('ui','unit') or only not in (None,real_test if suite=='ui'else real_sdk):raise ValueError('Real qualification runs only its bounded UI or SDK scenario on the primary owned Simulator')
        only = real_test if suite=='ui'else real_sdk
    if (only and 'TLSTests' in only) or (not only and suite in ('unit','all')):
        occupied=subprocess.run(['lsof','-t','-iTCP:'+str(TARGETS.port('unreachable')),'-sTCP:LISTEN'],capture_output=True,text=True)
        if occupied.stdout.strip():raise RuntimeError('Unreachable-endpoint test port 18449 is occupied; no process was changed')
    simulator=simulator_id(small)
    artifacts=ROOT/'.work/alpha/native-tests';artifacts.mkdir(parents=True,exist_ok=True,mode=0o700)
    run_id=time.strftime('%Y%m%d-%H%M%S')
    if real and suite=='unit':
        measured=ROOT/'artifacts/alpha/real-sdk-load.json'
        if measured.exists():
            previous=artifacts/(run_id+'-prior-real-sdk-load.json');previous.write_bytes(measured.read_bytes());previous.chmod(0o600)
        measured.write_text(json.dumps({'passed':False,'status':'running','measurementRunID':run_id},indent=2)+'\n')
    result=artifacts/(run_id+'.xcresult');log=artifacts/(run_id+'.log')
    command=['xcodebuild','test','-project',str(ROOT/'examples/ios-todo/ConnectTodo.xcodeproj'),'-scheme','ConnectTodo','-destination','id='+simulator,'-derivedDataPath',str(ROOT/'.work/alpha/DerivedData-Todo'),'-resultBundlePath',str(result),'-parallel-testing-enabled','NO']
    if only:command+=['-only-testing:'+only]
    elif suite=='unit':command+=['-only-testing:ConnectTodoTests']
    elif suite in ('ui','all'):
        if suite=='all':command+=['-only-testing:ConnectTodoTests']
        command+=['-only-testing:ConnectTodoUITests/ConnectTodoUITests/'+name for name in ['testNativeWorkflowRecoveryAndRevocation','testPreservedInstallUpgrade']]
    environment=dict(os.environ)
    environment['TEST_RUNNER_CONNECT_TEST_CREDENTIALS_PATH']=str(ROOT/'.work/alpha/dev/auth.json')
    environment['TEST_RUNNER_CONNECT_TEST_ORIGIN']=TARGETS.origin()
    if real:
        target=json.loads((TARGETS.work/'real-host/target.json').read_text())
        environment['TEST_RUNNER_CONNECT_TEST_ORIGIN']=target['origin']
        environment['TEST_RUNNER_CONNECT_TEST_CREDENTIALS_PATH']=str(TARGETS.work/'real-host/auth.json')
        environment['TEST_RUNNER_CONNECT_TEST_REAL_QUALIFICATION']='1'
    for name in ['unreachable','untrusted','wrong_host']:
        environment['TEST_RUNNER_CONNECT_TEST_'+name.upper()+'_ORIGIN']=TARGETS.origin(name)
    print('Running native iOS tests:',suite,'on owned simulator',simulator,flush=True)
    with ExitStack() as resources:
        api=None
        if (only and 'TLSTests' in only) or (not only and suite in ('unit','all')):
            from expired_tls import serving
            environment['TEST_RUNNER_CONNECT_TEST_EXPIRED_ORIGIN']=resources.enter_context(serving())
        if real:
            from real_test_support import connected
            api=resources.enter_context(connected())
        control=resources.enter_context(running(simulator,api_override=api,run_id=run_id))
        subprocess.run(['xcrun','simctl','ui',simulator,'appearance','light'],check=True,capture_output=True)
        environment['TEST_RUNNER_CONNECT_TEST_CONTROL_PATH']=str(control)
        if suite in ('ui','all'):
            subprocess.run(['xcrun','simctl','uninstall',simulator,'org.example.urbitconnect.todo'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        with log.open('w')as stream:
            log.chmod(0o600)
            process=subprocess.run(command,env=environment,stdout=stream,stderr=subprocess.STDOUT)
    if result.exists():
        summary=subprocess.run(['xcrun','xcresulttool','get','test-results','summary','--path',str(result)],capture_output=True,text=True)
        if summary.returncode==0:
            report=json.loads(summary.stdout)
            safe={key:report.get(key)for key in ['title','result','totalTestCount','passedTests','failedTests','skippedTests','expectedFailures']}
            print(json.dumps(safe,indent=2))
            (artifacts/(run_id+'-summary.json')).write_text(json.dumps(safe,indent=2)+'\n')
            print('Private xcresult:',result)
            if report.get('totalTestCount',0)==0 or report.get('skippedTests',0)or report.get('expectedFailures',0):return 1
        else:print('Could not read native result summary; inspect private log.');return 1
    else:
        print('No xcresult was produced; inspect private log:',log);return 1
    if real and suite=='unit' and process.returncode==0:
        path=ROOT/'artifacts/alpha/real-sdk-load.json';measured=json.loads(path.read_text())
        validate_real_sdk_evidence(measured,safe,run_id)
        import release_check
        measured.update(passed=True,status='passed',privateResult=result.name,source={group:release_check.tree(group)['sha256']for group in ['desk','sdk/swift','examples/ios-todo']})
        path.write_text(json.dumps(measured,indent=2)+'\n')
    if process.returncode == 0 and ((real and suite=='ui') or (not real and not only and suite in ('ui', 'all'))):
        from export_native_evidence import export
        export(result, small,real)
        if real:
            import release_check
            report={'passed':True,'realShip':True,'normalSystemTLS':True,'privateResult':result.name,'simulator':simulator,'cases':safe['totalTestCount'],'source':{group:release_check.tree(group)['sha256'] for group in ['desk','sdk/swift','examples/ios-todo']}}
            (ROOT/'artifacts/alpha/real-native.json').write_text(json.dumps(report,indent=2)+'\n')
    return process.returncode
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--suite',choices=['unit','ui','all'],default='all');parser.add_argument('--only');parser.add_argument('--small',action='store_true');parser.add_argument('--real',action='store_true');args=parser.parse_args();sys.exit(run(args.suite,args.only,args.small,args.real))
