"""Prepare private owner-browser acceptance credentials on authorized connect-dev.

Run on reference-host after the verified baseline install. Never print or pass the code
or cookie in argv. This owner context is test infrastructure, never an SDK input.
"""
import http.cookiejar
import json
from pathlib import Path
import re
import sys
import urllib.parse
import urllib.request
sys.path.insert(0, str(Path.home() / '.local/share/urbit-connect-alpha'))
from real_install import ROOT, command, request

origin = sys.argv[1]
target = json.loads((ROOT / 'target.json').read_text())
assert target['project'] == '/absolute/project' and target['pier'] == '/mnt/harbor/piers/connect-dev'
ship = request('/api/v1/ships/' + target['harborShipId'])
assert ship['pierPath'] == target['pier'] and ship['identity'] == target['ship'] and ship['state'] == 'running'
info = json.load(urllib.request.urlopen(origin + '/connect/v1/info', timeout=15))
assert info['ship'] == target['ship'] and not info['development'] and info['protocolVersion'] == 1
assert not info['configured'] or info['issuer'] == origin + '/connect'
code_output = command(target, '+code', 'private-owner-login')
codes = re.findall(r'~?[a-z]{6}(?:-[a-z]{6}){3}', code_output)
assert codes, 'Owner browser login unavailable; inspect private terminal log'
code = codes[-1].lstrip('~'); jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
login = urllib.request.Request(origin + '/~/login', data=urllib.parse.urlencode({'password': code}).encode(), method='POST')
with opener.open(login, timeout=30) as response: assert response.status == 200; response.read()
cookie = '; '.join(c.name + '=' + c.value for c in jar); assert cookie
bootstrap = json.load(opener.open(origin + '/connect/owner/v1/bootstrap', timeout=15))
configure = urllib.request.Request(origin + '/connect/owner/v1/configure', data=json.dumps({'issuer': origin + '/connect'}).encode(), headers={'Content-Type': 'application/json', 'Origin': origin, 'X-Connect-CSRF': bootstrap['csrf']}, method='POST')
with opener.open(configure, timeout=15) as response: assert response.status == 200; response.read()
auth = ROOT / 'auth.json'; auth.write_text(json.dumps({'code': code, 'cookie': cookie})); auth.chmod(0o600)
print(json.dumps({'ownerBrowserContextPrepared': True, 'credentialsPrinted': False, 'issuerConfigured': True}))
