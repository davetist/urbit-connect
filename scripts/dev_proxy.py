from targets import TARGETS
"""Own the loopback HTTPS proxy through a private supervisor, never a foreign PID."""
import argparse
import json
import os
from pathlib import Path
import secrets
import socketserver
import subprocess
import sys
import threading
import time
from dev_ship import ROOT, MARKER, prepare_state, rpc
STATE=ROOT/'.work/alpha/proxy'

def serve(state):
    config=json.loads((ROOT/'toolchain.json').read_text())
    environment=dict(os.environ,XDG_CONFIG_HOME=str(ROOT/'.work/alpha/caddy-config'),XDG_DATA_HOME=str(ROOT/'.work/alpha/caddy-data'))
    log=(ROOT/'.work/alpha/logs/caddy.log').open('ab');os.chmod(log.name,0o600)
    process=subprocess.Popen([str(ROOT/config['caddy']['localPath']),'run','--config',str(ROOT/'.work/alpha/Caddyfile'),'--adapter','caddyfile'],cwd=ROOT,env=environment,stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True)
    secret=json.loads((state/MARKER).read_text())['secret'];socket_path='/tmp/connect-proxy-'+secrets.token_hex(10)+'.sock'
    class Handler(socketserver.StreamRequestHandler):
        def handle(self):
            try:
                request=json.loads(self.rfile.readline(65536))
                if not secrets.compare_digest(request.get('secret',''),secret):raise ValueError('Unauthorized proxy control')
                if request['action']=='status':result={'alive':process.poll()is None,'pid':process.pid,'https':TARGETS.origin()}
                elif request['action']=='stop':
                    if process.poll()is None:
                        process.terminate()
                        try:process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            # An outage fixture must interrupt long polls as well.
                            # Signal only the supervisor's own Popen child.
                            process.kill();process.wait(timeout=5)
                    result={'exitCode':process.returncode};threading.Thread(target=server.shutdown,daemon=True).start()
                else:raise ValueError('Unknown proxy operation')
            except Exception as error:result={'error':str(error)}
            self.wfile.write((json.dumps(result)+'\n').encode())
    with socketserver.ThreadingUnixStreamServer(socket_path,Handler)as server:
        os.chmod(socket_path,0o600);metadata=state/'supervisor.json';metadata.write_text(json.dumps({'socket':socket_path}));metadata.chmod(0o600)
        try:server.serve_forever()
        finally:log.close();Path(socket_path).unlink(missing_ok=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['start','serve','status','stop']);parser.add_argument('--state-dir',type=Path,default=STATE);args=parser.parse_args();TARGETS.require_owned();state=prepare_state(args.state_dir)
    if args.action=='serve':serve(state);return
    if args.action=='start':
        try:
            result=rpc(state,'status')
            if result['alive']:print(json.dumps(result));return
        except (OSError,RuntimeError):pass
        with (state/'supervisor.log').open('ab')as log:
            subprocess.Popen([sys.executable,__file__,'serve','--state-dir',str(state)],stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True)
        for _ in range(100):
            time.sleep(.1)
            try:
                result=rpc(state,'status')
                if not result['alive']:raise RuntimeError('Proxy exited; inspect private caddy.log')
                time.sleep(.3);print(json.dumps(result));return
            except (FileNotFoundError,ConnectionError):continue
        raise TimeoutError('Proxy supervisor did not start')
    print(json.dumps(rpc(state,args.action)))
if __name__=='__main__':main()
