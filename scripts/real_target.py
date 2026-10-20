"""Explicit private configuration for optional real-host development tools."""
import os
from pathlib import Path, PurePosixPath
import re
import urllib.parse


def require_target(target, project=None):
    project = project if project is not None else os.environ.get('CONNECT_TEST_PROJECT')
    if not project or not Path(project).is_absolute():
        raise ValueError('An absolute CONNECT_TEST_PROJECT must be explicitly configured')
    if (target.get('approved') is not True or target.get('project') != str(project)
            or target.get('pier') != '/mnt/harbor/piers/connect-dev'):
        raise ValueError('No explicitly approved connect-dev target matches this project')
    origin = target.get('origin', '')
    parsed = urllib.parse.urlsplit(origin)
    if (parsed.scheme != 'https' or not parsed.hostname or parsed.username is not None
            or parsed.password is not None or parsed.path or parsed.query or parsed.fragment
            or any(character.isspace() for character in origin)):
        raise ValueError('The private target must specify an exact HTTPS origin')
    parsed.port  # Reject malformed port values before any network operation.
    return target


def remote_tool(target, name):
    root = PurePosixPath(target.get('remoteToolsDirectory', ''))
    if not root.is_absolute() or root == PurePosixPath('/') or '..' in root.parts:
        raise ValueError('An absolute private remoteToolsDirectory is required')
    if name not in {'real_install.py', 'netem_host.py'}:
        raise ValueError('Unknown real-host tool')
    return str(root / name)


def ssh_arguments(target):
    for field in ('sshHost', 'sshUser', 'sshHostKeyAlias'):
        if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.:-]*', target.get(field, '')):
            raise ValueError('Explicit private SSH host, user and host-key alias are required')
    paths = {}
    for field in ('sshIdentityFile', 'sshKnownHostsFile'):
        path = Path(target.get(field, ''))
        if not path.is_absolute() or not path.is_file():
            raise ValueError('Explicit absolute SSH identity and known-hosts files are required')
        paths[field] = str(path)
    return ['ssh', '-F', '/dev/null', '-i', paths['sshIdentityFile'],
            '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes',
            '-o', 'StrictHostKeyChecking=yes', '-o', 'HostKeyAlias=' + target['sshHostKeyAlias'],
            '-o', 'UserKnownHostsFile="' + paths['sshKnownHostsFile'].replace('\\', '\\\\').replace('"', '\\"') + '"',
            '-o', 'GlobalKnownHostsFile=/dev/null', '-o', 'UpdateHostKeys=no']
