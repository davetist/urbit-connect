"""Private controls for an explicitly selected, owned disposable Connect fixture.

This helper has no adapter-specific defaults and never starts or stops a ship.
"""
import json
from pathlib import Path
import socket
import stat
import subprocess
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]


def hoon_text(value):
    return "'" + value.replace('\\', '\\\\').replace("'", "\\'") + "'"


def jam(noun):
    """Encode the small, unshared noun used by the local Khan request."""
    bits = 0
    position = 0

    def write(value, length):
        nonlocal bits, position
        bits |= value << position
        position += length

    def encode(value):
        if isinstance(value, tuple):
            write(1, 2)
            encode(value[0])
            encode(value[1])
            return
        value = value if isinstance(value, int) else int.from_bytes(value.encode(), 'little')
        write(0, 1)
        if value == 0:
            write(1, 1)
            return
        width = value.bit_length()
        length = width.bit_length()
        write(1 << length, length + 1)
        write(width - (1 << (length - 1)), length - 1)
        write(value, width)

    encode(noun)
    return bits.to_bytes((position + 7) // 8, 'little')


def cell(*values):
    result = values[-1]
    for value in reversed(values[:-1]):
        result = (value, result)
    return result


class Fixture:
    def __init__(self, *, directory, fixture_id, origin, ca, owner_file, control_socket, vere):
        self.directory = Path(directory).absolute()
        if self.directory.is_symlink() or any(p.is_symlink() for p in self.directory.parents):
            raise ValueError('Fixture path must not traverse symlinks')
        if not self.directory.is_relative_to(ROOT / '.work'):
            raise ValueError('Disposable fixture must be under this project .work directory')
        marker = self.directory / '.owned-fixture.json'
        if marker.is_symlink() or json.loads(marker.read_text()) != {'project': str(ROOT), 'fixture': fixture_id}:
            raise ValueError('Fixture ownership does not match the explicit project and fixture ID')
        if self.directory.stat().st_mode & 0o077:
            raise ValueError('Fixture directory must be private (mode 700)')
        parts = urllib.parse.urlsplit(origin)
        if (parts.scheme != 'https' or parts.hostname not in ('localhost', '127.0.0.1')
                or parts.username or parts.password or parts.path or parts.query or parts.fragment
                or parts.port is None or not 1024 <= parts.port <= 65535):
            raise ValueError('An explicit loopback HTTPS origin with an unprivileged port is required')
        self.origin = origin
        self.ca = self.owned_path(ca)
        self.owner_file = self.owned_path(owner_file)
        self.control_socket = self.owned_path(control_socket)
        if self.owner_file.stat().st_mode & 0o077:
            raise ValueError('Owner credential file must be private (mode 600)')
        if not stat.S_ISSOCK(self.control_socket.stat().st_mode):
            raise ValueError('Control path is not a live Unix socket')
        self.vere = Path(vere).resolve(strict=True)
        self.replies = 0

    def owned_path(self, path):
        path = Path(path).absolute()
        if path.is_symlink() or any(p.is_symlink() for p in path.parents):
            raise ValueError('Fixture inputs must not traverse symlinks')
        if not path.is_relative_to(self.directory):
            raise ValueError('CA, private owner file and control socket must belong to the selected fixture')
        return path.resolve(strict=True)

    def control(self, expression):
        payload = jam(cell(0, 'fyrd', 'base', 'khan-eval', 'noun', 'ted-eval', expression))
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as stream:
            stream.settimeout(120)
            stream.connect(str(self.control_socket))
            stream.sendall(b'\0' + len(payload).to_bytes(4, 'little') + payload)

            def receive(size):
                chunks = bytearray()
                while len(chunks) < size:
                    chunk = stream.recv(size - len(chunks))
                    if not chunk:
                        raise RuntimeError('Fixture control socket closed before its complete reply')
                    chunks.extend(chunk)
                return bytes(chunks)

            header = receive(5)
            size = int.from_bytes(header[1:], 'little')
            if header[0] != 0 or size > 16 * 1024 * 1024:
                raise RuntimeError('Invalid fixture control reply framing')
            data = header + receive(size)
        decoded = subprocess.run([str(self.vere), 'eval', '-cn'], input=data,
                                 capture_output=True, check=True).stdout.decode().strip()
        self.replies += 1
        if not decoded.startswith('[0 %avow 0 %noun '):
            # Never put source expressions, codes or grants into the console/logs.
            target = self.directory / 'generic-control-error.txt'
            target.write_text(decoded)
            target.chmod(0o600)
            raise RuntimeError('Fixture control expression failed; inspect private generic-control-error.txt')
        return decoded.removeprefix('[0 %avow 0 %noun ').removesuffix(']')

    def verify_ship(self):
        result = self.control('=/  m  (strand ,vase)  ;<  now=@da  bind:m  get-time  ;<  our=@p  bind:m  get-our  (pure:m !>([our .^(? %j /~zod/fake/(scot %da now))]))')
        if result != '0 0':
            raise ValueError('Control socket must belong to a fake ~zod')

    def json_expression(self, expression):
        result = self.control('=/  m  (strand ,vase)  ;<  now=@da  bind:m  get-time  (pure:m !>((en:json:html ' + expression + ')))')
        if result.startswith('%'):
            result = result[1:]
        elif result.startswith("'"):
            result = result[1:-1].replace("\\'", "'").replace('\\\\', '\\')
        else:
            value = int(result, 0)
            result = value.to_bytes((value.bit_length() + 7) // 8, 'little').decode()
        return json.loads(result)

    def scry(self, agent, path):
        return self.json_expression(f'.^(json %gx /~zod/{agent}/(scot %da now)/{path}/json)')

    def poke(self, target, mark, noun):
        self.control(f'=/  m  (strand ,vase)  ;<  ~  bind:m  (poke-our %{target} %{mark} !>({noun}))  ;<  ~  bind:m  (sleep ~s1)  (pure:m !>(~))')

    def install_probe(self):
        """Import only the fixed-response generic test consumer, never an adapter."""
        source = ROOT / 'integrations/grant-probe/desk'
        self.control('=/  m  (strand ,vase)  ;<  now=@da  bind:m  get-time  ?:  (~(has in .^((set desk) %cd /~zod//(scot %da now))) %grant-probe)  (pure:m !>(~))  ;<  ~  bind:m  (poke-our %hood %kiln-merge !>([%grant-probe ~zod %base da+now %init]))  ;<  ~  bind:m  (sleep ~s1)  (pure:m !>(~))')
        for hoon_phase in (True, False):
            prefix = '=/  m  (strand ,vase)  ;<  now=@da  bind:m  get-time  '
            entries = []
            for index, path in enumerate(sorted(source.rglob('*'))):
                if not path.is_file() or (path.suffix == '.hoon') != hoon_phase:
                    continue
                mark = path.suffix[1:]
                raw = path.read_bytes()
                digits = format(int.from_bytes(raw, 'little'), 'x')
                atom = '0x' + '.'.join(reversed([digits[max(0, end - 4):end] for end in range(len(digits), 0, -4)]))
                clay_path = '/' + str(path.relative_to(source)).replace('.', '/')
                prefix += f'=/  tube{index}=tube:clay  .^(tube:clay %cc /~zod/grant-probe/(scot %da now)/mime/{mark})  '
                length = format(len(raw), ',').replace(',', '.')
                prefix += f'=/  val{index}=vase  (tube{index} !>(`mime`[/text/plain [{length} {atom}]]))  '
                entries.append(f'[{clay_path} %ins %{mark} val{index}]')
            self.control(prefix + ';<  ~  bind:m  (send-raw-card [%pass /import %arvo %c %info [%grant-probe %.y ~[' + ' '.join(entries) + ']]])  ;<  ~  bind:m  (sleep ~s1)  (pure:m !>(~))')
        self.poke('hood', 'kiln-install', '[%grant-probe ~zod %grant-probe]')
        self.scry('grant-probe', 'result')
