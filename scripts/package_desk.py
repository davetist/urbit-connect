from targets import TARGETS
"""Package reproducible desk sources and verify installation on an owned fresh fake ship."""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.request
from dev_ship import ROOT,prepare_state,rpc

ERRORS=('event failed','nest-fail','-find.','syntax error','find-fork','FAILED','ford: build failed')
def checked_command(state,command):
    reply=rpc(state,'command',command=command,timeout=180)['output']
    diagnostic=state/'desk-command.log';diagnostic.write_text(reply);diagnostic.chmod(0o600)
    if any(marker in reply for marker in ERRORS):raise RuntimeError('Desk command failed; inspect the private runtime log')
    return reply

def stage(state,source=None):
    state=prepare_state(state);source=source or ROOT/'desk';target=state/'zod/connect'
    if not target.is_dir()or target.is_symlink():raise ValueError('Create and mount %connect in the owned test ship first')
    previous=state/'staged-files.json'
    files={str(p.relative_to(source))for p in source.rglob('*')if p.is_file()}
    if previous.exists():
        for name in set(json.loads(previous.read_text()))-files:
            path=target/name
            if path.is_relative_to(target)and not path.is_symlink():path.unlink(missing_ok=True)
    for name in sorted(files):
        origin=source/name;dest=target/name
        if origin.is_symlink()or dest.is_symlink():raise ValueError('Desk symlinks are not supported')
        dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(origin,dest)
    checked_command(state,'|commit %connect');previous.write_text(json.dumps(sorted(files)))
    print('Staged and committed',len(files),'desk files in owned test ship')

def package():
    version=json.loads((ROOT/'release/version.json').read_text())['version']
    output=ROOT/('dist/connect-'+version+'.tgz');output.parent.mkdir(exist_ok=True)
    entries={str(p.relative_to(ROOT/'desk')):p.read_bytes()for p in(ROOT/'desk').rglob('*')if p.is_file()}
    manifest=''.join(hashlib.sha256(data).hexdigest()+'  '+name+'\n'for name,data in sorted(entries.items()))
    with output.open('wb')as raw,gzip.GzipFile(filename='',mode='wb',fileobj=raw,mtime=0)as zipped,tarfile.open(fileobj=zipped,mode='w')as archive:
        for name,data in sorted({'connect/'+name:data for name,data in entries.items()}.items()):
            info=tarfile.TarInfo(name);info.size=len(data);info.mode=0o644;info.mtime=0;archive.addfile(info,io.BytesIO(data))
        for name,data in [('MANIFEST.sha256',manifest.encode()),('LICENSE',(ROOT/'LICENSE').read_bytes()),('THIRD_PARTY/urbit-LICENSE.txt',(ROOT/'third_party/urbit/LICENSE.txt').read_bytes()),('THIRD_PARTY/landscape-NOTICE.md',(ROOT/'third_party/landscape/NOTICE.md').read_bytes())]:
            info=tarfile.TarInfo(name);info.size=len(data);info.mode=0o644;archive.addfile(info,io.BytesIO(data))
    digest=hashlib.sha256(output.read_bytes()).hexdigest();output.with_suffix('.tgz.sha256').write_text(digest+'  '+output.name+'\n');print('Packaged:',output.name,digest);return output

def verify_install(archive):
    state=prepare_state(TARGETS.work/('package-verification-'+time.strftime('%Y%m%d-%H%M%S')))
    extracted=state/'extracted';extracted.mkdir()
    with tarfile.open(archive)as bundle:
        for entry in bundle.getmembers():
            if not entry.isfile()or Path(entry.name).is_absolute()or'..'in Path(entry.name).parts:raise ValueError('Unsafe package entry')
            target=extracted/entry.name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(bundle.extractfile(entry).read())
    manifest=(extracted/'MANIFEST.sha256').read_text().splitlines()
    for line in manifest:
        digest,name=line.split('  ',1)
        if hashlib.sha256((extracted/'connect'/name).read_bytes()).hexdigest()!=digest:raise AssertionError('Package digest mismatch')
    command=[sys.executable,str(ROOT/'scripts/dev_ship.py'),'start','--state-dir',str(state),'--port',str(TARGETS.port('package_http'))]
    subprocess.run(command,check=True,capture_output=True)
    try:
        checked_command(state,'|new-desk %connect');checked_command(state,'|mount %connect');stage(state,extracted/'connect');checked_command(state,'|install our %connect')
        with urllib.request.urlopen(f"http://127.0.0.1:{TARGETS.port('package_http')}/connect/v1/info",timeout=30)as response:info=json.load(response)
        if info['protocolVersion']!=1 or not info['development']or info['configured']:raise AssertionError('Unexpected fresh installation')
        with urllib.request.urlopen(f"http://127.0.0.1:{TARGETS.port('package_http')}/apps/connect/",timeout=30)as response:
            if response.status!=200 or b'<div id="app"'not in response.read():raise AssertionError('Bundled owner UI did not load')
        print('PASS: fresh packaged desk installs and serves protocol 1 plus bundled UI')
        report=ROOT/'artifacts/alpha/package.json';report.parent.mkdir(parents=True,exist_ok=True);report.write_text(json.dumps({'archive':archive.name,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'files':len(manifest),'freshInstall':True,'state':state.name,'runtime':'4.6','kernel':408},indent=2)+'\n')
    finally:rpc(state,'stop',timeout=100)

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--state-dir',type=Path,default=ROOT/'.work/alpha/dev');parser.add_argument('--verify-install',action='store_true');parser.add_argument('--package-only',action='store_true');args=parser.parse_args()
    if not args.package_only and not args.verify_install:stage(args.state_dir)
    archive=package()
    if args.verify_install:verify_install(archive)
if __name__=='__main__':main()
