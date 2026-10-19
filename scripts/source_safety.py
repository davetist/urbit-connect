"""Read release inputs without following file or directory symlinks."""
import os
import json
from pathlib import Path
import stat
import subprocess

EXCLUDED = {'.work', '.git', '.build', 'node_modules', 'dist', 'DerivedData', 'xcuserdata', '__pycache__', '.DS_Store', 'test-results', 'playwright-report'}


def source_manifest(root):
    root = Path(root)
    names = json.loads((root / 'release/source-files.json').read_text())
    if not isinstance(names, list) or not all(isinstance(name, str) for name in names) or names != sorted(set(names)):
        raise ValueError('Invalid release source manifest')
    for name in names:
        path = Path(name)
        if (not name or path.is_absolute() or path.as_posix() != name or '..' in path.parts or '\\' in name
                or EXCLUDED.intersection(path.parts)
                or any(part == '.env' or (part.startswith('.env.') and part not in {'.env.example', '.env.sample'}) for part in path.parts)):
            raise ValueError('Unsafe release source path: ' + name)
    if (root / '.git').exists():
        tracked = set(subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z']).decode().strip('\0').split('\0'))
        if set(names) != tracked:
            raise ValueError('Release source manifest differs from tracked files')
    return names


def read_regular(root, relative):
    root = Path(root)
    relative = Path(relative)
    if relative.is_absolute() or not relative.parts or '..' in relative.parts:
        raise ValueError('Unsafe release source path: ' + str(relative))
    directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for part in relative.parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
            os.close(directory)
            directory = child
        descriptor = os.open(relative.parts[-1], os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory)
        try:
            if not stat.S_ISREG(os.fstat(descriptor).st_mode):
                raise ValueError('Non-regular release source: ' + str(relative))
            with os.fdopen(descriptor, 'rb') as stream:
                descriptor = -1
                return stream.read()
        finally:
            if descriptor != -1:
                os.close(descriptor)
    finally:
        os.close(directory)
