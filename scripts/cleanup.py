from targets import TARGETS
"""Stop owned development processes and remove trust only from the dedicated test environments."""
import json
from pathlib import Path
import shutil
import subprocess
from dev_ship import ROOT,MARKER,rpc

def main():
    TARGETS.require_owned()
    work=TARGETS.work
    for state in sorted(work.iterdir()):
        if not state.is_dir()or state.is_symlink()or not(state/MARKER).is_file()or not(state/'supervisor.json').is_file():continue
        if json.loads((state/MARKER).read_text()).get('project')!=str(ROOT):continue
        try:rpc(state,'stop',timeout=100);print('Stopped owned supervisor:',state.name)
        except (OSError,ConnectionError):pass
    for metadata in sorted((work/'dev').glob('simulator*.json')):
        owned=json.loads(metadata.read_text())
        if owned.get('project')!=str(ROOT) or owned.get('fixtureId')!=TARGETS.fixture_id:raise RuntimeError('Unowned Simulator marker')
        devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','--json'],text=True))['devices']
        device=next((d for group in devices.values()for d in group if d['udid']==owned['id']),None)
        if device and device['name']==owned['name']:
            if device['state']!='Booted':subprocess.run(['xcrun','simctl','boot',owned['id']],check=True)
            subprocess.run(['xcrun','simctl','terminate',owned['id'],'org.example.urbitconnect.todo'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            subprocess.run(['xcrun','simctl','keychain',owned['id'],'reset'],check=True)
            subprocess.run(['xcrun','simctl','shutdown',owned['id']],check=True)
            print('Reset test trust and shut down only the owned Simulator:',owned['name'])
    profile=work/'firefox-profile'
    if (profile/'cert9.db').exists():
        certutil=shutil.which('certutil')or'/opt/homebrew/opt/nss/bin/certutil'
        check=subprocess.run([certutil,'-L','-d','sql:'+str(profile),'-n','Connect Prototype Test CA'],capture_output=True)
        if check.returncode==0:subprocess.run([certutil,'-D','-d','sql:'+str(profile),'-n','Connect Prototype Test CA'],check=True)
        print('Removed test CA from the project Firefox profile')
    print('Named piers and private diagnostic evidence retained in .work. Run setup.py before testing again.')
if __name__=='__main__':main()
